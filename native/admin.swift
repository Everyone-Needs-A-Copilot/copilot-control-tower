//
// Copilot Control Tower — Admin mode (S4): the org-standup + governance
// window ("drive-the-agent"). Two faces, one binary: `control-tower-tray.swift`
// is the user face (Bob); this file is the Admin face (Earl). Reached via the
// tray's right-click menu ("Open Administration...") or `CT_OPEN_ADMIN=1` at
// launch (mirrors `CT_OPEN_WIZARD=1` for the wizard, see AppDelegate there).
//
// Ground truth, read together:
//   - docs/03-design/control-tower-admin-flow.md — THE flow this file builds
//     (surface inventory ADM-0..ADM-9/ADM-G*, per-screen states, the
//     drive-and-render seam per screen).
//   - docs/03-design/admin-agentic-setup.md — the engine/seam this UI drives
//     (`copilot admin bootstrap --json`, the GitHub sequence, integration-
//     per-layer, idempotent/additive/never-destroy).
//   - docs/03-design/control-tower-copy-deck.md Surface 3 — verbatim strings.
//   - docs/03-design/control-tower-visual-system.md — "Quiet Instrument".
//
// MOCK-BACKED, same status as `wizard.swift`: `copilot admin bootstrap --json`
// does not exist yet (WS-A unstarted). Review & run (ADM-8) simulates the
// engine's streamed `{step, result, detail}` with Swift structured
// concurrency (`Task { ... try? await Task.sleep(...) }`) advancing an
// ordered checklist in place — the UI computes nothing; it renders exactly
// what a real engine feed would send. Every other Configure surface (ADM-4..7)
// only assembles local state; nothing mutates GitHub until Review & run fires.
//
// Parse-never-compute (invariant #1): this file contains NO `gh` call, no
// GitHub API call, no existence check, no idempotency decision, and no
// red/green verdict logic beyond the mock stand-in for what the engine would
// have already decided. The mock functions below (`resolveOutcome`,
// `computePreflightChecks`) exist ONLY because there is no real engine to
// shell out to yet — they are flagged as the seam a real `copilot admin
// bootstrap --json` response will replace verbatim, exactly like
// `WizardModel`'s own mock transitions in `wizard.swift`.
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory` and the
// same discipline in `wizard.swift`/`control-tower-tray.swift`): no blocking
// `Process`/file I/O may run during a SwiftUI `@State`/`@StateObject` `init()`.
// `AdminModel.init()` is the implicit memberwise default (every `@Published`
// property has a literal default) — nothing here runs I/O or a subprocess at
// initialization time. All mock "engine" work is scheduled from a user action
// via `Task { ... await Task.sleep(...) }`, never from a property initializer.

import AppKit
import SwiftUI

// MARK: - Sidebar item inventory (ADM-0's window; ADM-1..ADM-9 + ADM-G1..G3
// are the sidebar rows — ADM-0/ADM-3 are the entry + the gate, not rows of
// their own beyond Connect GitHub).

enum AdminSection: String {
    case onboarding = "ONBOARDING"
    case governance = "GOVERNANCE"
}

/// TEMPORARY REVIEW OVERRIDE (Change 3): normally every downstream Admin
/// screen stays locked (`AdminItem.requiresGitHubGate`) until Connect GitHub
/// passes (`AdminModel.githubGateOpen`) — see `AdminSidebar.row(_:)` below,
/// the one call site that reads this. For review, every sidebar screen is
/// reachable regardless of connection state so all Admin surfaces can be
/// judged in one pass. The real gating logic (`requiresGitHubGate`,
/// `githubGateOpen`) is untouched; this only bypasses it. Flip back to
/// `false` to restore the real entitlement gating.
let allScreensUnlockedForReview = true

/// One row in the Admin sidebar. Order matches the admin-flow doc's own
/// surface inventory (§2) and nav diagram (§3): the two NEW spine surfaces
/// (Connect GitHub, Review & run) sit in reading-order position so the
/// sidebar itself reads as the drive-the-agent pipeline.
enum AdminItem: Int, CaseIterable, Identifiable {
    case prerequisites, contacts, connectGitHub, departmentsAccess, secretStore
    case seed, policySigners, reviewRun, preflight
    case addOffboard, analytics, secretStoreConfig
    var id: Int { rawValue }

    static let onboarding: [AdminItem] = [
        .prerequisites, .contacts, .connectGitHub, .departmentsAccess,
        .secretStore, .seed, .policySigners, .reviewRun, .preflight,
    ]
    static let governance: [AdminItem] = [.addOffboard, .analytics, .secretStoreConfig]

    var section: AdminSection { AdminItem.onboarding.contains(self) ? .onboarding : .governance }

    /// Copy deck §3.2 sidebar labels, verbatim, with the two NEW spine labels
    /// from the admin-flow doc's surface inventory (§2) slotted in.
    var sidebarLabel: String {
        switch self {
        case .prerequisites: return "Prerequisites"
        case .contacts: return "Contacts"
        case .connectGitHub: return "Connect GitHub"
        case .departmentsAccess: return "Repositories & teams"
        case .secretStore: return "Secret store"
        case .seed: return "Seed"
        case .policySigners: return "Policy signers"
        case .reviewRun: return "Review & run"
        case .preflight: return "Preflight"
        case .addOffboard: return "Add / offboard"
        case .analytics: return "Analytics"
        case .secretStoreConfig: return "Secret store config"
        }
    }

    /// "Connect GitHub gates everything downstream: Review & run is inert
    /// until the auth+scope preflight passes" (admin-flow §3). Preflight
    /// itself stays reachable even ungated (it is a read-only check that
    /// honestly renders "never run" until something exists to verify).
    var requiresGitHubGate: Bool {
        switch self {
        case .departmentsAccess, .secretStore, .seed, .policySigners, .reviewRun: return true
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .prerequisites: return "checklist"
        case .contacts: return "person.text.rectangle"
        case .connectGitHub: return "point.3.connected.trianglepath.dotted"
        case .departmentsAccess: return "person.2.badge.key.fill"
        case .secretStore: return "lock.doc"
        case .seed: return "doc.badge.gearshape"
        case .policySigners: return "signature"
        case .reviewRun: return "play.circle"
        case .preflight: return "checklist.checked"
        case .addOffboard: return "person.badge.minus"
        case .analytics: return "chart.bar.doc.horizontal"
        case .secretStoreConfig: return "lock.doc"
        }
    }
}

// MARK: - Shared secret-shape refusal (§6.3, the load-bearing safety
// interaction reused across every configure field on every Admin surface)

/// A small, deliberately conservative, fail-closed heuristic. This is a
/// UI-side input guard only (invariant #1 is not at stake here: this never
/// decides ecosystem state, it only decides "does this look like a secret
/// so I refuse to store it locally"). The real backstop is the engine's
/// step-5 leak-scan (`admin-agentic-setup.md` §1.3 step 5); this is the
/// field-level defense-in-depth companion (§6.3).
enum SecretShapeCheck {
    private static let knownPrefixes = [
        "sk-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "xox", "AKIA", "AIza", "eyJ",
    ]

    static func looksLikeSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("BEGIN PRIVATE KEY") || trimmed.contains("BEGIN RSA") { return true }
        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        // High-entropy heuristic: a long, unbroken, mixed-case-plus-digit
        // token with no spaces reads as a credential, not a name or a URL.
        guard trimmed.count >= 20, !trimmed.contains(" ") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./+="))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        let hasUpper = trimmed.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = trimmed.rangeOfCharacter(from: .lowercaseLetters) != nil
        return hasDigit && hasUpper && hasLower
    }

    static func looksLikeURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}

/// The one hard block reused on every configure field (copy deck §3.6).
/// Rejects inline; the rejected value is never written into the bound
/// `value` (not stored, not logged) — a constraint, not a warning dialog.
struct SecretGuardedField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = ""
    var helpText: String? = nil
    @State private var refused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            TextField(placeholder, text: Binding(
                get: { value },
                set: { newValue in
                    if SecretShapeCheck.looksLikeSecret(newValue) {
                        refused = true
                    } else {
                        refused = false
                        value = newValue
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityValue(refused ? "That looks like a secret. This setting never holds secrets." : "")

            if refused {
                secretRefusalLine
            } else if let helpText {
                Text(helpText)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
    }

    private var secretRefusalLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(Color(nsColor: .systemRed))
                .accessibilityHidden(true)
            Text("That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .systemRed))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ADM-3 Connect GitHub

enum GitHubRefusalReason: String, CaseIterable, Identifiable {
    case unauthenticated, notOwner, missingScope, orgMissing
    var id: String { rawValue }

    func line(org: String) -> String {
        switch self {
        case .unauthenticated:
            return "You're not signed in to GitHub yet, so I can't set up your organization."
        case .notOwner:
            return "Your GitHub account isn't an owner of \(org), so it can't create the org's spaces. Ask an owner to run this, or to make you one."
        case .missingScope:
            return "Your GitHub sign-in is missing the access it needs to set up your organization."
        case .orgMissing:
            return "I can't find the \(org) organization on GitHub. It has to be created on github.com first (that needs billing and a person)."
        }
    }

    var command: String? { self == .missingScope ? "gh auth refresh -s admin:org -s repo" : nil }

    var fixOwnerLine: String {
        switch self {
        case .unauthenticated: return "Run gh auth login, then check again."
        case .notOwner: return "This is owned by your GitHub org owner."
        case .missingScope: return "Run the command above, then check again."
        case .orgMissing: return "Create the organization on github.com, then check again."
        }
    }

    /// Dev-only label for the mock outcome picker below (never shown to a
    /// real operator; the real engine would never expose a picker here).
    var devLabel: String {
        switch self {
        case .unauthenticated: return "Not signed in"
        case .notOwner: return "Not an org owner"
        case .missingScope: return "Missing scope"
        case .orgMissing: return "Org doesn't exist"
        }
    }
}

enum GitHubCheckState: Equatable {
    case notChecked
    case checking
    case passed
    case refused(GitHubRefusalReason)
    case degraded
}

/// Dev-only picker selection (`GitHubCheckState` carries an associated value
/// on `.refused` and is deliberately not `Hashable` — this flat enum is only
/// the picker's own tag type, mapped to `GitHubCheckState` at use).
enum GitHubDevOutcome: String, CaseIterable, Identifiable {
    case passed, unauthenticated, notOwner, missingScope, orgMissing, degraded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .passed: return "Pass"
        case .unauthenticated: return GitHubRefusalReason.unauthenticated.devLabel
        case .notOwner: return GitHubRefusalReason.notOwner.devLabel
        case .missingScope: return GitHubRefusalReason.missingScope.devLabel
        case .orgMissing: return GitHubRefusalReason.orgMissing.devLabel
        case .degraded: return "Degraded"
        }
    }

    var checkState: GitHubCheckState {
        switch self {
        case .passed: return .passed
        case .unauthenticated: return .refused(.unauthenticated)
        case .notOwner: return .refused(.notOwner)
        case .missingScope: return .refused(.missingScope)
        case .orgMissing: return .refused(.orgMissing)
        case .degraded: return .degraded
        }
    }
}

// MARK: - ADM-4 Departments & access (org identity, departments-as-you-go,
// integration-per-layer, member/team grants)

struct IntegrationDeclaration: Identifiable, Equatable {
    let id = UUID()
    var integrationID: String
    var requiresSecret: String
    var storeScope: String
}

enum GrantRole: String, CaseIterable, Identifiable {
    case read, write
    var id: String { rawValue }
    var label: String { self == .read ? "Read (can join)" : "Write (can author)" }
}

struct MemberGrant: Identifiable, Equatable {
    let id = UUID()
    var username: String
    var role: GrantRole
}

struct AdminDepartment: Identifiable, Equatable {
    static func == (lhs: AdminDepartment, rhs: AdminDepartment) -> Bool { lhs.id == rhs.id }
    let id: String
    var name: String
    var integrations: [IntegrationDeclaration] = []
    var members: [MemberGrant] = []
}

/// Known-classified integrations (open decision 5, `admin-agentic-setup.md`
/// §5.5) — a constrained picker where classification exists, with the
/// "add custom" free-text escape everywhere else (`IntegrationPickerField`).
/// Workday is deliberately IN this catalog but never pre-declared anywhere:
/// declaring it nowhere is the entire "absence = non-existence" mechanism
/// (engine §2) — the picker offers it, the seed simply never carries it.
enum IntegrationCatalog {
    static let known = ["salesforce", "microsoft365", "hubspot", "slack", "workday", "zendesk"]

    static func displayName(_ id: String) -> String {
        switch id {
        case "salesforce": return "Salesforce"
        case "microsoft365": return "Microsoft 365"
        case "hubspot": return "HubSpot"
        case "slack": return "Slack"
        case "workday": return "Workday"
        case "zendesk": return "Zendesk"
        default: return id.isEmpty ? "" : id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

/// A constrained picker with an "add custom" escape (the ratified default:
/// "covers picker + free-text"). `id` is a picker from the classified
/// catalog; choosing "Add custom..." reveals a guarded free-text field.
struct IntegrationPickerField: View {
    @Binding var integrationID: String
    @State private var customMode: Bool = false

    var body: some View {
        if customMode || (!integrationID.isEmpty && !IntegrationCatalog.known.contains(integrationID)) {
            HStack(spacing: 8) {
                SecretGuardedField(label: "", value: $integrationID, placeholder: "Integration name")
                Button("Choose from list") {
                    customMode = false
                    if !IntegrationCatalog.known.contains(integrationID) {
                        integrationID = IntegrationCatalog.known[0]
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } else {
            Picker("", selection: Binding(
                get: { integrationID.isEmpty ? IntegrationCatalog.known[0] : integrationID },
                set: { newValue in
                    if newValue == "__custom__" {
                        customMode = true
                        integrationID = ""
                    } else {
                        integrationID = newValue
                    }
                }
            )) {
                ForEach(IntegrationCatalog.known, id: \.self) { known in
                    Text(IntegrationCatalog.displayName(known)).tag(known)
                }
                Text("Add custom...").tag("__custom__")
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }
}

// MARK: - ADM-8 Review & run (the trigger-and-render checklist)

/// Result tokens the engine emits, mapped to the plain row words (admin-flow
/// §7.2 table). `ready` is this build's own word for the two read-only
/// checks (step 0 auth, step 5 leak-scan, step 6 verify) that resolve to a
/// single pass reading rather than created/already-present.
enum RunOutcome: Equatable {
    case ready
    case created
    case alreadyPresent
    case stopped(detail: String, owner: String)
    case failed(detail: String, owner: String)

    var word: String {
        switch self {
        case .ready: return "Ready"
        case .created: return "Created"
        case .alreadyPresent: return "Already there"
        case .stopped: return "Stopped"
        case .failed(let detail, _): return detail
        }
    }

    /// `already-present` and the other calm outcomes are never rendered in
    /// an error color (never-destroy made legible, admin-flow §7.2).
    var isCalm: Bool {
        switch self {
        case .ready, .created, .alreadyPresent: return true
        case .stopped, .failed: return false
        }
    }

    var detail: String? {
        switch self {
        case .stopped(let detail, _), .failed(let detail, _): return detail
        default: return nil
        }
    }

    var owner: String? {
        switch self {
        case .stopped(_, let owner), .failed(_, let owner): return owner
        default: return nil
        }
    }
}

enum RunRowState: Equatable {
    case waiting
    case working
    case resolved(RunOutcome)
}

struct RunStepRow: Identifiable, Equatable {
    let id: String
    let title: String
    var state: RunRowState = .waiting
}

enum RunPhase: Equatable {
    case idle
    case working
    case done
    case degraded
    case refused
}

// MARK: - ADM-9 Preflight (setup check, red/green, unknown-never-green, owner-named)

enum PreflightStatus { case pass, fail, unknown }

struct PreflightCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: PreflightStatus
    let detail: String
    let owner: String?
}

enum PreflightRunState: Equatable { case neverRun, running, done }

// MARK: - ADM-G1 Deprovision (rendered, never triggered)

struct DeprovisionEvent {
    let personName: String
    let retainedWork: [String]
    let removedCount: Int
    let secretsInvolved: Bool
}

// MARK: - The Admin model

/// One model backing the whole Admin window, same "one big observable model"
/// shape `WizardModel` uses. Nothing here runs I/O at `init()` — every mock
/// transition is scheduled from a user action via `Task { ... }`.
@MainActor
final class AdminModel: ObservableObject {
    // Navigation
    @Published var selected: AdminItem = .prerequisites

    /// ADM-0's own overview screen (Change 1). Shown once per window open,
    /// same rhythm as `WizardModel`'s Welcome -> Get Started. Nothing here
    /// runs I/O; it is a plain flag flipped by a user action, never by
    /// `init()` (this file's own AttributeGraph constraint, see header).
    @Published var showingWelcome = true

    func getStarted() {
        showingWelcome = false
    }

    // Handoff header (admin-flow §4; copy deck §3.1)
    struct HandoffInfo { let publisherStatus: String; let setupVersion: String; let nextOwner: String }
    @Published var handoff: HandoffInfo? = HandoffInfo(
        publisherStatus: "Publisher done", setupVersion: "v1.4.2", nextOwner: "you (Admin)"
    )
    var handoffLine: String {
        guard let handoff else { return "Not started yet" }
        return "\(handoff.publisherStatus) · Setup \(handoff.setupVersion) · Next: \(handoff.nextOwner)"
    }

    // ADM-1 Prerequisites (a checklist to work down by hand; nothing here is
    // itself performed by the app — copy deck §3.3: "None of it is done
    // here". These specific list items are this build's own invented content
    // (not in the copy deck, which only gives title/intro/empty) — plain,
    // Earl-appropriate language, flagged here for a cw pass.)
    struct PrerequisiteItem: Identifiable { let id = UUID(); let text: String; var checked = false }
    @Published var prerequisites: [PrerequisiteItem] = [
        PrerequisiteItem(text: "You can sign in to GitHub with an account that can become an org owner."),
        PrerequisiteItem(text: "Your organization exists on GitHub, or you know who will create it."),
        PrerequisiteItem(text: "You know who owns billing for that organization."),
        PrerequisiteItem(text: "You have a person in mind for each department you plan to set up."),
    ]

    // ADM-2 Contacts (copy deck §3.4)
    @Published var publisherContact = ""
    @Published var adminContact = ""
    @Published var pointOfContact = ""
    @Published var contactsSaved = false

    // ADM-3 Connect GitHub
    @Published var orgName = "acme-co"
    @Published var githubState: GitHubCheckState = .notChecked
    /// Dev-only: which mock outcome the next "Check access" resolves to.
    @Published var devGitHubOutcome: GitHubDevOutcome = .passed

    var githubGateOpen: Bool { githubState == .passed }

    func checkGitHubAccess() {
        githubState = .checking
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard case .checking = self.githubState else { return }
            self.githubState = self.devGitHubOutcome.checkState
        }
    }

    // ADM-4 Departments & access
    @Published var orgIntegrations: [IntegrationDeclaration] = [
        IntegrationDeclaration(integrationID: "salesforce", requiresSecret: "SALESFORCE_API_KEY", storeScope: "org"),
        IntegrationDeclaration(integrationID: "microsoft365", requiresSecret: "MS365_TOKEN", storeScope: "org"),
    ]
    @Published var departments: [AdminDepartment] = [
        AdminDepartment(
            id: "sales", name: "Sales",
            integrations: [IntegrationDeclaration(integrationID: "hubspot", requiresSecret: "HUBSPOT_KEY", storeScope: "dept/sales")],
            members: [MemberGrant(username: "asha", role: .read), MemberGrant(username: "morgan", role: .write)]
        ),
        AdminDepartment(id: "engineering", name: "Engineering"),
    ]
    @Published var newDepartmentName = ""

    func addDepartment() {
        let trimmed = newDepartmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
        guard !departments.contains(where: { $0.id == slug }) else { newDepartmentName = ""; return }
        departments.append(AdminDepartment(id: slug, name: trimmed))
        newDepartmentName = ""
    }

    func removeDepartment(_ id: String) {
        departments.removeAll { $0.id == id }
    }

    // ADM-5 Secret store (copy deck §3.6)
    @Published var storeType = "Infisical"
    @Published var storeAddress = ""
    @Published var storeAddressError: String?
    @Published var storeTeamScopes: [(id: UUID, team: String, scope: String)] = []
    @Published var storeConnected = false
    @Published var newScopeTeam = ""

    func connectSecretStore() {
        guard SecretShapeCheck.looksLikeURL(storeAddress) else {
            storeAddressError = "That doesn't look like a valid address."
            return
        }
        storeAddressError = nil
        storeConnected = true
    }

    // ADM-6 Seed (copy deck §3.7)
    enum SeedPRState: Equatable { case idle, opening, opened(ref: String) }
    @Published var seedValidated = false
    @Published var seedIssueCount = 0
    @Published var seedPRState: SeedPRState = .idle
    @Published var usageDataOptIn = false

    func validateSeed() {
        var issues = 0
        if orgName.trimmingCharacters(in: .whitespaces).isEmpty { issues += 1 }
        if departments.isEmpty { issues += 1 }
        if policySigners.isEmpty { issues += 1 }
        seedIssueCount = issues
        seedValidated = issues == 0
    }

    func openSeedPullRequest() {
        guard seedValidated else { return }
        seedPRState = .opening
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.seedPRState = .opened(ref: "#123")
        }
    }

    // ADM-7 Policy signers
    struct PolicySigner: Identifiable, Equatable { let id = UUID(); var name: String }
    @Published var policySigners: [PolicySigner] = [PolicySigner(name: "asha")]
    @Published var newSignerName = ""

    func addSigner() {
        let trimmed = newSignerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SecretShapeCheck.looksLikeSecret(trimmed) else { newSignerName = ""; return }
        policySigners.append(PolicySigner(name: trimmed))
        newSignerName = ""
    }

    func removeSigner(_ id: UUID) {
        policySigners.removeAll { $0.id == id }
    }

    // ADM-8 Review & run
    @Published var runPhase: RunPhase = .idle
    @Published var runRows: [RunStepRow] = []
    private var runCount = 0
    private var materializedDepartmentIDs: Set<String> = []
    private var orgSpaceMaterialized = false
    /// Dev-only: forces one row to resolve `Stopped` (the leak-scan refusal,
    /// §7.3) so the refused state can be judged without a real engine.
    @Published var devForceStopStep: String? = nil

    func departmentID(fromStepID stepID: String) -> String? {
        for dept in departments {
            if stepID.hasPrefix("\(dept.id)-") { return dept.id }
        }
        return nil
    }

    private func buildRunRows() -> [RunStepRow] {
        var rows: [RunStepRow] = [
            RunStepRow(id: "auth", title: "Checked your access"),
            RunStepRow(id: "base-perm", title: "Set the org to read-only by default"),
            RunStepRow(id: "org-repo", title: "Created your organization space"),
        ]
        for dept in departments {
            rows.append(RunStepRow(id: "\(dept.id)-repo", title: "Setting up the \(dept.name) department"))
            rows.append(RunStepRow(id: "\(dept.id)-team", title: "\(dept.name) team"))
            rows.append(RunStepRow(id: "\(dept.id)-grant", title: "Who can join \(dept.name)"))
            rows.append(RunStepRow(id: "\(dept.id)-members", title: "Add people to \(dept.name)"))
        }
        rows.append(RunStepRow(id: "seed", title: "Write your setup file"))
        rows.append(RunStepRow(id: "leak-scan", title: "Safety check"))
        rows.append(RunStepRow(id: "verify", title: "Setup check"))
        return rows
    }

    private func resolveOutcome(for stepID: String) -> RunOutcome {
        if devForceStopStep == stepID {
            return .stopped(
                detail: "I stopped before pushing because something in your setup looked like a secret. Setup files never carry secrets. Fix it and run again.",
                owner: "Admin"
            )
        }
        switch stepID {
        case "auth": return .ready
        case "base-perm": return .alreadyPresent
        case "org-repo": return orgSpaceMaterialized ? .alreadyPresent : .created
        case "seed": return runCount > 0 ? .alreadyPresent : .created
        case "leak-scan": return .ready
        case "verify": return .ready
        default:
            if let deptID = departmentID(fromStepID: stepID) {
                return materializedDepartmentIDs.contains(deptID) ? .alreadyPresent : .created
            }
            return .created
        }
    }

    /// Fires the single trigger. Mocks the engine's streamed
    /// `{step, result, detail}` with structured concurrency — real code will
    /// replace this method's body with a line-by-line read of
    /// `copilot admin bootstrap --json`'s stdout, resolving each row from the
    /// parsed line instead of a local guess (the row/summary rendering below
    /// does not change).
    func runBootstrap() {
        guard runPhase != .working else { return }
        runRows = buildRunRows()
        runPhase = .working
        Task { [weak self] in
            await self?.streamRun()
        }
    }

    private func streamRun() async {
        for index in runRows.indices {
            runRows[index].state = .working
            try? await Task.sleep(nanoseconds: 260_000_000)
            let outcome = resolveOutcome(for: runRows[index].id)
            runRows[index].state = .resolved(outcome)
            if case .stopped = outcome {
                runPhase = .refused
                return
            }
            if case .failed = outcome {
                runPhase = .refused
                return
            }
        }
        orgSpaceMaterialized = true
        materializedDepartmentIDs.formUnion(departments.map { $0.id })
        runCount += 1
        devForceStopStep = nil
        runPhase = .done
    }

    /// Dev-only: simulates the stream becoming unreadable mid-run (§7.2
    /// degraded state) so it can be judged without a real broken engine.
    func simulateDegradedRun() {
        guard !runRows.isEmpty else { return }
        runPhase = .working
        Task { [weak self] in
            guard let self else { return }
            for index in self.runRows.indices.prefix(2) {
                self.runRows[index].state = .working
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.runRows[index].state = .resolved(self.resolveOutcome(for: self.runRows[index].id))
            }
            self.runPhase = .degraded
        }
    }

    var runSummary: String {
        let resolved: [RunOutcome] = runRows.compactMap {
            if case .resolved(let outcome) = $0.state { return outcome }
            return nil
        }
        guard !resolved.isEmpty else { return "" }
        let createdCount = resolved.filter { $0 == .created }.count
        let alreadyCount = resolved.filter { $0 == .alreadyPresent }.count
        let allResolved = runRows.allSatisfy {
            if case .resolved = $0.state { return true }
            return false
        }
        if allResolved, createdCount == 0, alreadyCount > 0, resolved.allSatisfy({ $0.isCalm }) {
            return "Nothing to redo. Everything's already in place."
        }
        var parts: [String] = []
        if createdCount > 0 { parts.append("\(createdCount) created") }
        if alreadyCount > 0 { parts.append("\(alreadyCount) already there") }
        var summary = parts.isEmpty ? "0 changes" : parts.joined(separator: ", ") + "."
        if runPhase == .working { summary += " Still working." }
        return summary
    }

    // ADM-9 Preflight
    @Published var preflightState: PreflightRunState = .neverRun
    @Published var preflightChecks: [PreflightCheck] = []

    func runPreflight() {
        guard preflightState != .running else { return }
        preflightState = .running
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.preflightChecks = self.computePreflightChecks()
            self.preflightState = .done
        }
    }

    private func computePreflightChecks() -> [PreflightCheck] {
        let orgReady = orgSpaceMaterialized
        let deptReady = !departments.isEmpty && departments.allSatisfy { materializedDepartmentIDs.contains($0.id) }
        let grantsReady = departments.allSatisfy { !$0.members.isEmpty }
        let membersReady = departments.contains { !$0.members.isEmpty }
        let seedReady = seedValidated && !policySigners.isEmpty
        let storeReady = storeConnected

        return [
            PreflightCheck(
                name: "Your organization's shared space", status: orgReady ? .pass : .fail,
                detail: orgReady ? "Ready" : "Run Review & run to create your organization's shared space.",
                owner: orgReady ? nil : "Admin"
            ),
            PreflightCheck(
                name: "Department spaces", status: deptReady ? .pass : .fail,
                detail: deptReady ? "Ready" : "One or more department spaces haven't been set up yet.",
                owner: deptReady ? nil : "Admin"
            ),
            PreflightCheck(
                name: "Team access", status: grantsReady ? .pass : .fail,
                detail: grantsReady ? "Ready" : "One or more departments have no one who can join yet.",
                owner: grantsReady ? nil : "Admin"
            ),
            PreflightCheck(
                name: "People added", status: membersReady ? .pass : .unknown,
                detail: membersReady ? "Ready" : "Couldn't check this. No one has been added to a department yet.",
                owner: membersReady ? nil : "Admin"
            ),
            PreflightCheck(
                name: "Your setup file", status: seedReady ? .pass : .fail,
                detail: seedReady ? "Ready" : "Your setup file hasn't been checked over and signed yet.",
                owner: seedReady ? nil : "Admin / Policy signer"
            ),
            PreflightCheck(
                name: "Shared secret store", status: storeReady ? .pass : .unknown,
                detail: storeReady ? "Ready" : "Couldn't check this. Connect your shared secret store first.",
                owner: storeReady ? nil : "IT infra"
            ),
            PreflightCheck(
                name: "Foundation reference", status: .pass,
                detail: "Ready", owner: nil
            ),
        ]
    }

    // ADM-G1 Add / offboard
    @Published var lastDeprovision: DeprovisionEvent? = DeprovisionEvent(
        personName: "Jordan Reyes", retainedWork: ["Sales onboarding notes.docx"], removedCount: 3, secretsInvolved: false
    )

    func simulateDeprovision(secretsInvolved: Bool) {
        lastDeprovision = DeprovisionEvent(
            personName: "Jordan Reyes",
            retainedWork: secretsInvolved ? [] : ["Sales onboarding notes.docx"],
            removedCount: secretsInvolved ? 5 : 3,
            secretsInvolved: secretsInvolved
        )
    }

    // ADM-G2 Analytics
    @Published var analyticsEnabled = false

    // Dev-only restart, mirrors `WizardModel.restart()`.
    func restart() {
        selected = .prerequisites
        showingWelcome = true
        handoff = HandoffInfo(publisherStatus: "Publisher done", setupVersion: "v1.4.2", nextOwner: "you (Admin)")
        githubState = .notChecked
        runPhase = .idle
        runRows = []
        runCount = 0
        materializedDepartmentIDs = []
        orgSpaceMaterialized = false
        devForceStopStep = nil
        preflightState = .neverRun
        preflightChecks = []
        contactsSaved = false
        seedValidated = false
        seedPRState = .idle
    }
}

// MARK: - Reusable small views

/// A firm, distinct card for the load-bearing refuse-not-weaken moment
/// (ADM-3's refusal and ADM-8's `Stopped` row share this language). Never
/// offers a bypass, `--force`, or `--skip-verify` — only the honest fix and
/// **Check again** / **Run again**.
struct RefusalCard: View {
    let line: String
    let command: String?
    let fixOwnerLine: String
    let actionLabel: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(Color(nsColor: .systemRed))
                    .accessibilityHidden(true)
                Text(line)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let command {
                HStack {
                    Text(command)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(command, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(fixOwnerLine)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            Button(actionLabel, action: action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .systemRed).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GitHub access, not ready, and how to fix it")
    }
}

struct AdminSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One row of the ADM-8 streamed checklist. Shape + word carry the state
/// (never color alone); `already-present` reads calm, never as an error.
struct RunRowView: View {
    let row: RunStepRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            Text(row.title)
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(accessibilityWord)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var icon: some View {
        switch row.state {
        case .waiting:
            Image(systemName: "circle")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .working:
            ProgressView().controlSize(.small)
        case .resolved(let outcome):
            if outcome.isCalm {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            } else {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(Color(nsColor: .systemRed))
            }
        }
        EmptyView().accessibilityHidden(true)
    }

    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .waiting:
            Text("Waiting").font(.caption).foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .working:
            Text("Working").font(.caption).foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .resolved(let outcome):
            VStack(alignment: .trailing, spacing: 2) {
                Text(outcome.word)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(nsColor: outcome.isCalm ? .secondaryLabelColor : .systemRed))
                if let owner = outcome.owner {
                    Text(owner)
                        .font(.caption2)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
    }

    private var accessibilityWord: String {
        switch row.state {
        case .waiting: return "waiting"
        case .working: return "working"
        case .resolved(let outcome): return outcome.word.lowercased()
        }
    }
}

/// One row of the ADM-9 Preflight checklist: shape + color + text, never
/// color alone; `unknown` is rendered distinctly and is NEVER green.
struct PreflightRowView: View {
    let check: PreflightCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(check.status == .pass ? "Ready" : check.detail)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let owner = check.owner {
                Text(owner)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .separatorColor).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.name), \(accessibilityStatus), \(check.owner ?? "")")
    }

    @ViewBuilder private var icon: some View {
        switch check.status {
        case .pass:
            Image(systemName: "checkmark.circle.fill").foregroundColor(Color(nsColor: .systemGreen))
        case .fail:
            Image(systemName: "xmark.circle.fill").foregroundColor(Color(nsColor: .systemRed))
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundColor(Color(nsColor: .systemOrange))
        }
    }

    private var accessibilityStatus: String {
        switch check.status {
        case .pass: return "ready"
        case .fail: return check.detail
        case .unknown: return "couldn't check this"
        }
    }
}

// MARK: - Admin sidebar

struct AdminSidebar: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HANDOFF")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Text(model.handoffLine)
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Handoff status: \(model.handoffLine)")
            }

            Section {
                ForEach(AdminItem.onboarding) { item in row(item) }
            } header: {
                Text(AdminSection.onboarding.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }

            Section {
                ForEach(AdminItem.governance) { item in row(item) }
            } header: {
                Text(AdminSection.governance.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        .listStyle(.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Administration")
    }

    private func row(_ item: AdminItem) -> some View {
        let locked = !allScreensUnlockedForReview && item.requiresGitHubGate && !model.githubGateOpen
        let isCurrent = model.selected == item

        return Button {
            guard !locked else { return }
            model.selected = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .foregroundColor(isCurrent ? Color(nsColor: .controlAccentColor) : Color(nsColor: .secondaryLabelColor))
                    .frame(width: 16)
                Text(item.sidebarLabel)
                    .font(.body.weight(isCurrent ? .medium : .regular))
                    .foregroundColor(locked ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: isCurrent ? .labelColor : .secondaryLabelColor))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isCurrent ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .help(locked ? "Not available yet. Connect GitHub first." : "")
        .accessibilityLabel(item.sidebarLabel)
        .accessibilityValue(locked ? "not available yet, connect GitHub first" : (isCurrent ? "current" : ""))
    }
}

// MARK: - ADM-0 Welcome (NEW, Change 1): the Admin face's own overview
// screen, styled and structured after scripts/publisher_setup.swift's
// Welcome (hero -> why this matters -> what's required) so the two native
// apps read as one family. Shown once per window open, ahead of the
// existing Prerequisites checklist; "Get Started" hands off to it, the same
// rhythm as the wizard's Welcome -> Get Started -> Detect.
struct AdminWelcomeView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    heroImage

                    VStack(spacing: 12) {
                        Text("Welcome, Admin.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .labelColor))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("You're standing up your organization's Copilot Solutioning Ecosystem on GitHub: the organization and department repositories, teams, access grants, a shared secret store connection, and the seed config everything else reads from. Once it's in place, everyone on your team inherits the right tools automatically.")
                            .font(.body)
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AdminSectionCard(title: "Why this matters") {
                        VStack(alignment: .leading, spacing: 14) {
                            infoRow(symbol: "person.2.badge.key.fill", text: "Everyone's machine stays current with exactly the tools they're entitled to, nothing more.")
                            infoRow(symbol: "checkmark.shield", text: "Access is decided by GitHub repository membership, not by anything typed into this app.")
                            infoRow(symbol: "arrow.triangle.2.circlepath", text: "Nothing here is ever destroyed. Running this again only adds what's new and leaves everything else untouched.")
                        }
                    }

                    AdminSectionCard(title: "What you'll need") {
                        VStack(alignment: .leading, spacing: 14) {
                            infoRow(symbol: "person.badge.key", text: "A GitHub account with admin:org access on your organization.")
                            infoRow(symbol: "building.2", text: "Your organization already created on github.com. This never creates the organization itself, that needs billing and a person.")
                            infoRow(symbol: "list.bullet", text: "A rough list of the departments and integrations you want set up. You can always add more later.")
                        }
                    }

                    Text("The secret store never receives a key here, only a reference to where your keys already live.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 32)
                .padding(.top, 48)
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
                .keyboardShortcut(.cancelAction)

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

    /// Illustration reads only at ~40pt+ (below that its detail collapses
    /// into an unreadable blob, see `ControlTowerGlyph`'s own doc comment)
    /// — 76pt matches the wizard's own Welcome hero exactly.
    private var heroImage: some View {
        Image(nsImage: ControlTowerGlyph.load(targetHeight: 76))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 76, height: 76)
            .accessibilityLabel("Copilot Control Tower")
    }

    private func infoRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(nsColor: .systemBlue))
                .imageScale(.large)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Admin root view

struct AdminRootView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        if model.showingWelcome {
            AdminWelcomeView(model: model)
                .frame(minWidth: 900, idealWidth: 1080, minHeight: 640, idealHeight: 760)
        } else {
            NavigationSplitView {
                AdminSidebar(model: model)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
            } detail: {
                ScrollView {
                    detail
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 900, idealWidth: 1080, minHeight: 640, idealHeight: 760)
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.selected.section.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .systemBlue))
                .textCase(.uppercase)

            switch model.selected {
            case .prerequisites: PrerequisitesView(model: model)
            case .contacts: ContactsView(model: model)
            case .connectGitHub: ConnectGitHubView(model: model)
            case .departmentsAccess: DepartmentsAccessView(model: model)
            case .secretStore: SecretStoreView(model: model)
            case .seed: SeedView(model: model)
            case .policySigners: PolicySignersView(model: model)
            case .reviewRun: ReviewRunView(model: model)
            case .preflight: PreflightView(model: model)
            case .addOffboard: AddOffboardView(model: model)
            case .analytics: AnalyticsView(model: model)
            case .secretStoreConfig: SecretStoreConfigView(model: model)
            }
        }
    }
}

// MARK: - ADM-1 Prerequisites (copy deck §3.3)

struct PrerequisitesView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Before you begin")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("A short checklist of what you'll need on hand to stand up the ecosystem. None of it is done here, this is just so nothing stops you halfway.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($model.prerequisites) { $item in
                    Toggle(isOn: $item.checked) {
                        Text(item.text)
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

// MARK: - ADM-2 Contacts (copy deck §3.4)

struct ContactsView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Who's who")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Record who owns this setup, so the handoff is never guesswork. These names show in the handoff banner and in the setup check.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 14) {
                SecretGuardedField(label: "Publisher", value: $model.publisherContact)
                SecretGuardedField(label: "Admin", value: $model.adminContact)
                SecretGuardedField(label: "Point of contact", value: $model.pointOfContact)
            }
        }

        HStack {
            Button("Save") {
                model.contactsSaved = true
            }
            .buttonStyle(.borderedProminent)

            if model.contactsSaved {
                Text("Saved.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }
}

// MARK: - ADM-3 Connect GitHub

struct ConnectGitHubView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Connect GitHub")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Before anything changes, I check your GitHub access can do the job. This never touches your organization, it only reads.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "") {
            SecretGuardedField(label: "Organization", value: $model.orgName, placeholder: "acme-co")
        }

        Group {
            switch model.githubState {
            case .notChecked:
                idleCard(text: "Not checked yet.")
            case .checking:
                workingCard(text: "Checking your GitHub access...")
            case .passed:
                passedCard
            case .refused(let reason):
                RefusalCard(
                    line: reason.line(org: model.orgName),
                    command: reason.command,
                    fixOwnerLine: reason.fixOwnerLine,
                    actionLabel: "Check again",
                    action: { model.checkGitHubAccess() }
                )
            case .degraded:
                degradedCard
            }
        }

        devOutcomePicker
    }

    private func idleCard(text: String) -> some View {
        AdminSectionCard(title: "") {
            HStack {
                Text(text)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Button("Check access") { model.checkGitHubAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func workingCard(text: String) -> some View {
        AdminSectionCard(title: "") {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }

    private var passedCard: some View {
        AdminSectionCard(title: "") {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Text("Your GitHub access can set up \(model.orgName).")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
                Button("Check again") { model.checkGitHubAccess() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var degradedCard: some View {
        AdminSectionCard(title: "") {
            HStack {
                Text("Something stopped me from checking your access, so I won't guess.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Check again") { model.checkGitHubAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// DEV-ONLY: picks which mock outcome the next "Check access" resolves
    /// to, so every refusal reason (and the degraded state) can be judged
    /// without a real `gh` credential. Same convention as the tray's own
    /// "Preview state (dev only)" menu.
    private var devOutcomePicker: some View {
        HStack(spacing: 8) {
            Text("Dev preview outcome:")
                .font(.caption2)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Picker("", selection: $model.devGitHubOutcome) {
                ForEach(GitHubDevOutcome.allCases) { outcome in
                    Text(outcome.label).tag(outcome)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }
}

// MARK: - ADM-4 Departments & access (copy deck §3.5)

struct DepartmentsAccessView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Departments and access")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Access is how someone joins a department. Give a team read access and its people can join the department. Give write access and they can author it.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "Departments") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.departments) { dept in
                    HStack {
                        Text(dept.name).font(.body).foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Button {
                            model.removeDepartment(dept.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .accessibilityLabel("Remove \(dept.name)")
                    }
                }
                HStack {
                    SecretGuardedField(label: "", value: $model.newDepartmentName, placeholder: "Department name")
                    Button("Add a department") { model.addDepartment() }
                        .buttonStyle(.bordered)
                }
            }
        }

        Text("Adding a department here only adds what's new when you next run Review and run. It never touches anything already there.")
            .font(.callout)
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "Shared integrations at your organization") {
            integrationList(binding: $model.orgIntegrations, emptyText: "No shared integrations at your organization yet.")
        }

        ForEach($model.departments) { $dept in
            AdminSectionCard(title: "Shared integrations at \(dept.name)") {
                integrationList(binding: $dept.integrations, emptyText: "No shared integrations at \(dept.name) yet.")
            }
        }

        ForEach($model.departments) { $dept in
            AdminSectionCard(title: "Who can join \(dept.name)") {
                membersSection(dept: $dept)
            }
        }
    }

    private func integrationList(binding: Binding<[IntegrationDeclaration]>, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if binding.wrappedValue.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            ForEach(binding) { $entry in
                HStack(spacing: 10) {
                    IntegrationPickerField(integrationID: $entry.integrationID)
                    SecretGuardedField(label: "", value: $entry.requiresSecret, placeholder: "requires_secret name")
                        .frame(maxWidth: 200)
                    Button {
                        binding.wrappedValue.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            Button("Add an integration") {
                binding.wrappedValue.append(IntegrationDeclaration(integrationID: IntegrationCatalog.known[0], requiresSecret: "", storeScope: "org"))
            }
            .buttonStyle(.bordered)
        }
    }

    private func membersSection(dept: Binding<AdminDepartment>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let readNames = dept.wrappedValue.members.filter { $0.role == .read }.map(\.username)
            let writeNames = dept.wrappedValue.members.filter { $0.role == .write }.map(\.username)

            if dept.wrappedValue.members.isEmpty {
                Text("No one can join this department yet. Give a team read access to let them in.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            } else {
                if !readNames.isEmpty {
                    Text("People on this team can join the \(dept.wrappedValue.name) department: \(readNames.joined(separator: ", ")).")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !writeNames.isEmpty {
                    Text("These people can author the \(dept.wrappedValue.name) department: \(writeNames.joined(separator: ", ")).")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AddMemberRow(dept: dept)
        }
    }
}

private struct AddMemberRow: View {
    @Binding var dept: AdminDepartment
    @State private var username = ""
    @State private var role: GrantRole = .read

    var body: some View {
        HStack(spacing: 10) {
            SecretGuardedField(label: "", value: $username, placeholder: "GitHub username")
            Picker("", selection: $role) {
                ForEach(GrantRole.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            Button("Add") {
                let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                dept.members.append(MemberGrant(username: trimmed, role: role))
                username = ""
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - ADM-5 Secret store (copy deck §3.6)

struct SecretStoreView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Connect your shared secret store")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Your organization's shared integrations (Salesforce, Workday, Microsoft) get their keys from one shared store. Connect it once here. You never paste a key into this app.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Store type").font(.caption.weight(.semibold)).foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Picker("", selection: $model.storeType) {
                        Text("Infisical").tag("Infisical")
                        Text("OpenBao").tag("OpenBao")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                SecretGuardedField(
                    label: "Store address", value: $model.storeAddress, placeholder: "https://secrets.acme-co.internal",
                    helpText: "This is a web address, not a secret."
                )
                if let error = model.storeAddressError {
                    Text(error).font(.caption).foregroundColor(Color(nsColor: .systemRed))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Which teams can use it").font(.caption.weight(.semibold)).foregroundColor(Color(nsColor: .secondaryLabelColor))
                    ForEach(model.storeTeamScopes, id: \.id) { scope in
                        Text("\(scope.team) → \(scope.scope)")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    HStack {
                        SecretGuardedField(label: "", value: $model.newScopeTeam, placeholder: "team name")
                        Button("Add a team") {
                            let trimmed = model.newScopeTeam.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            model.storeTeamScopes.append((id: UUID(), team: trimmed, scope: "org"))
                            model.newScopeTeam = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Button("Connect") { model.connectSecretStore() }
                        .buttonStyle(.borderedProminent)
                    if model.storeConnected {
                        Text("Connected. This will be included when you open your setup pull request.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }
}

// MARK: - ADM-6 Seed (copy deck §3.7)

struct SeedView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Build your setup")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Fill in the sections below and Control Tower writes the setup file for you, then opens a pull request. You never touch a config file or a terminal.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "What this will create") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Copilots: Claude Copilot, CLI Copilot, Codex Copilot, Knowledge Copilot")
                Text("Departments: \(model.departments.map(\.name).joined(separator: ", "))")
                Text("Integration references: \((model.orgIntegrations + model.departments.flatMap(\.integrations)).map { IntegrationCatalog.displayName($0.integrationID) }.joined(separator: ", "))")
                Text("Policy signers: \(model.policySigners.map(\.name).joined(separator: ", "))")
                Text("Usage data: \(model.usageDataOptIn ? "on" : "off")")
            }
            .font(.body.monospaced())
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }

        Toggle("Share anonymous usage data", isOn: $model.usageDataOptIn)
            .toggleStyle(.switch)

        HStack {
            Button("Check it over") { model.validateSeed() }
                .buttonStyle(.bordered)
            Text(model.seedIssueCount == 0 && model.seedValidated ? "Everything checks out." : (model.seedIssueCount > 0 ? "\(model.seedIssueCount) things to fix" : ""))
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }

        HStack {
            Button("Open pull request") { model.openSeedPullRequest() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.seedValidated || model.seedPRState == .opening)

            switch model.seedPRState {
            case .idle: EmptyView()
            case .opening:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Opening pull request...").font(.callout).foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            case .opened(let ref):
                Text("Opened pull request \(ref).").font(.callout).foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
    }
}

// MARK: - ADM-7 Policy signers

struct PolicySignersView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Policy signers")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Signers sign your setup file and set who can approve changes to it. Add the people who own that responsibility.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 10) {
                if model.policySigners.isEmpty {
                    Text("No signers yet. Add the people who own this responsibility.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
                ForEach(model.policySigners) { signer in
                    HStack {
                        Image(systemName: "signature").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text(signer.name).font(.body).foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Button {
                            model.removeSigner(signer.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
                HStack {
                    SecretGuardedField(label: "", value: $model.newSignerName, placeholder: "GitHub username")
                    Button("Add a signer") { model.addSigner() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - ADM-8 Review & run (the trigger-and-render moment)

struct ReviewRunView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Review & run")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("This is where your organization actually gets set up. You'll fire one setup and watch each repository, team, and grant land as it happens. Nothing here deletes or overwrites anything already there, so running it again is always safe.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        if model.runPhase == .idle {
            reviewCard
        }

        if !model.runRows.isEmpty {
            checklistCard
        }

        if model.runPhase == .degraded {
            AdminSectionCard(title: "") {
                HStack {
                    Text("I couldn't read the rest of that, so I won't guess.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Run again") { model.runBootstrap() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }

        if model.runPhase == .done {
            Button("Run the setup check") { model.selected = .preflight }
                .buttonStyle(.borderedProminent)
        }

        Text("Prefer to run this from the terminal? The same setup is available as an open-source command.")
            .font(.caption)
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))

        devControls
    }

    private var reviewCard: some View {
        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 12) {
                Text("About to set up: \(model.orgName) · \(model.departments.count) department\(model.departments.count == 1 ? "" : "s") (\(model.departments.map(\.name).joined(separator: ", ")))")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)

                let integrationNames = (model.orgIntegrations + model.departments.flatMap(\.integrations))
                    .map { IntegrationCatalog.displayName($0.integrationID) }
                if !integrationNames.isEmpty {
                    Text(integrationNames.joined(separator: ", ") + " at your organization")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }

                Text("This adds and updates. It never deletes or overwrites anything already there.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    triggerButton
                }
            }
        }
    }

    @ViewBuilder private var triggerButton: some View {
        if model.runPhase == .working {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Setting up your organization...")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else {
            Button("Set up my org") { model.runBootstrap() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.githubGateOpen)
        }
    }

    private var checklistCard: some View {
        AdminSectionCard(title: "") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.runRows.enumerated()), id: \.element.id) { index, row in
                    RunRowView(row: row)
                    if index < model.runRows.count - 1 { Divider() }
                }
                if !model.runSummary.isEmpty {
                    Divider().padding(.vertical, 8)
                    Text("Summary: \(model.runSummary)")
                        .font(.callout.weight(.medium))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if model.runPhase == .done {
                    HStack {
                        Spacer()
                        Button("Run again") { model.runBootstrap() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    /// DEV-ONLY: forces the `Stopped` row / a mid-stream degrade so both
    /// states can be judged without a real leak-scan or a broken feed.
    private var devControls: some View {
        HStack(spacing: 12) {
            Button("Simulate a stopped step (dev)") {
                model.devForceStopStep = "leak-scan"
                model.runBootstrap()
            }
            Button("Simulate stream lost (dev)") { model.simulateDegradedRun() }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }
}

// MARK: - ADM-9 Preflight (copy deck §3.8)

struct PreflightView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Run the setup check")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("An honest red and green list before you hand this over. Every red names who has to fix it, so you always know who to chase.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        switch model.preflightState {
        case .neverRun:
            AdminSectionCard(title: "") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Run the setup check before you hand this over. It catches blockers before your organization does.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Run the setup check") { model.runPreflight() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .running:
            AdminSectionCard(title: "") {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking your setup...")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        case .done:
            AdminSectionCard(title: "") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.preflightChecks.enumerated()), id: \.offset) { index, check in
                        PreflightRowView(check: check)
                        if index < model.preflightChecks.count - 1 { Divider() }
                    }
                    Divider().padding(.vertical, 8)
                    Text(preflightSummary)
                        .font(.callout.weight(.medium))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button("Run it again") { model.runPreflight() }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var preflightSummary: String {
        let failing = model.preflightChecks.filter { $0.status == .fail }.count
        let unknown = model.preflightChecks.filter { $0.status == .unknown }.count
        if failing == 0 && unknown == 0 { return "Everything's ready to hand over." }
        var parts: [String] = []
        if failing > 0 { parts.append("\(failing) thing\(failing == 1 ? "" : "s") must be fixed") }
        if unknown > 0 { parts.append("\(unknown) couldn't be checked") }
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - ADM-G1 Add / offboard (copy deck §3.9, add-department re-run reused)

struct AddOffboardView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Add / offboard")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("Add a department or a person here. Setting up again only adds what's new and never touches what's already there.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        Button("Go add a department") { model.selected = .departmentsAccess }
            .buttonStyle(.bordered)

        Divider()

        Text("Someone left")
            .font(.title2.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("When a person's access is revoked, this is what happened on their Mac. Control Tower renders it, it never triggers it.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        if let event = model.lastDeprovision {
            AdminSectionCard(title: "") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Their access was revoked and their shared keys were rotated.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .labelColor))
                    if event.retainedWork.isEmpty {
                        Text("No unsaved personal work was in the way.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    } else {
                        Text("Their unsaved work was kept: \(event.retainedWork.joined(separator: ", ")).")
                            .font(.callout.weight(.medium))
                            .foregroundColor(Color(nsColor: .labelColor))
                    }
                    Text("\(event.removedCount) item(s) removed.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    if event.secretsInvolved {
                        Text("Heads up: secrets were involved in this. Your IT team has been told.")
                            .font(.callout.weight(.medium))
                            .foregroundColor(Color(nsColor: .systemRed))
                    }
                }
            }
        } else {
            Text("I couldn't read the result of this, so I won't guess.")
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }

        HStack(spacing: 12) {
            Button("Simulate offboarding (dev)") { model.simulateDeprovision(secretsInvolved: false) }
            Button("Simulate with secrets touched (dev)") { model.simulateDeprovision(secretsInvolved: true) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }
}

// MARK: - ADM-G2 Analytics (copy deck §3.10)

struct AnalyticsView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Usage data")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("A plain switch for whether anonymous usage data leaves this Mac. It's off by default, and only changes if you turn it on.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        Toggle("Share anonymous usage data", isOn: $model.analyticsEnabled)
            .toggleStyle(.switch)

        Text(model.analyticsEnabled
            ? "What this would share"
            : "Off. Nothing is shared unless you turn this on and your organization signs off on it.")
            .font(.callout)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - ADM-G3 Secret store config (copy deck §3.11)

struct SecretStoreConfigView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        Text("Shared secret store")
            .font(.title.weight(.semibold))
            .foregroundColor(Color(nsColor: .labelColor))

        Text("A read-only look at where your organization's shared secret keys come from. It's set once in your organization's signed setup, never edited here.")
            .font(.body)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

        AdminSectionCard(title: "Where your shared keys come from") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.storeConnected ? model.storeAddress : "Not connected yet.")
                    .font(.body.monospaced())
                    .foregroundColor(Color(nsColor: .labelColor))
                Text("This comes from your organization's signed setup. It isn't editable here, by design.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Admin window controller

/// Owns the Admin window + its `AdminModel` for the app's lifetime, same
/// singleton shape as `WizardWindowController`. `isReleasedWhenClosed =
/// false` so closing the window never deallocates it — the next `show()`
/// reopens with whatever state it was last in (admin-flow §4: "Admin state
/// persists ... nothing is lost by closing mid-pipeline").
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
