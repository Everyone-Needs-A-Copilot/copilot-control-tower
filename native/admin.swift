//
// Copilot Control Tower — Admin mode.
// `control-tower-tray.swift` is the User face (Bob); this file plus
// `native/admin-support.swift` is the separately packaged Admin face (Earl).
// The Admin build opens this window directly as a conventional macOS app.
//
// Ground truth, read together (see docs/HANDOFF-ADMIN-MODE-BUILD.md for the
// fuller map):
//   - docs/03-design/admin-experience-interaction-design.md — THE per-surface
//     spec this file implements screen-for-screen (16 surfaces, states,
//     refusals, the new sidebar IA).
//   - docs/03-design/control-tower-copy-deck.md Surface 3 (§3.1-3.18) —
//     verbatim strings. Every user-facing string in this file is either lifted
//     verbatim from there or marked `[cw]` in a comment where the design doc
//     flagged it as new/finalized-here.
//   - docs/01-architecture/admin-standup-contract.md — the real machine seams:
//     the brief formats (§1), the in-app transaction amendment, and the verify
//     JSON (§3). `scripts/admin_bootstrap.sh` implements the deterministic
//     plan/apply/verify engine side of that contract.
//   - docs/03-design/control-tower-visual-system.md — the "Quiet Instrument"
//     language (shape-first status, `surface.field` for code/handoff blocks,
//     no raw error strings, no time estimates, no em-dashes).
//
// REAL vs HONESTLY-DEGRADED (no mocks pretending to be real):
//   - Connect GitHub (this file, below) checks the bundled Admin tools, parses
//     `gh auth status --json`, and verifies active organization ownership
//     through GitHub's membership API. Missing identity/scopes route through
//     GitHub's browser authorization; no terminal remediation is rendered.
//   - Review and the Setup check (`native/admin-support.swift`) execute the real
//     `scripts/admin_bootstrap.sh --verify --brief <path> --json` and render
//     its plan/check rows verbatim; the explicit setup action invokes its
//     additive apply path. If the engine or `gh` is missing, it renders the
//     honest degraded state (`unknown`, never a fabricated green).
//   - The brief writer (`native/admin-support.swift`) persists both the
//     human-readable Markdown and machine-readable JSON transaction input.
//   - Surfaces with no real backing seam yet (Someone left's team/key listing,
//     Org setup's live `ecosystem.yml` fetch) render their designed
//     empty/degraded state honestly and are marked `// CONTRACT SEAM:` —
//     never invented mock data.
//
// CRITICAL SwiftUI/AppKit ordering constraint (a real prior crash — see
// `.claude/memory`): no blocking `Process`/file I/O may run during a SwiftUI
// `@State`/`@StateObject` `init()` or first layout. `AdminModel.init()` does
// no I/O. Every shell-out and file operation below runs from a `.task {}` or
// a user action, off the main thread (`ShellRunner`/`AdminIO`), delivering
// back on `@MainActor` (`AdminModel` itself is `@MainActor`-isolated, same
// convention as `WizardModel` in `wizard.swift`).
//
// File split: this file holds the process/file I/O primitives, the shared
// secret-shape guard, the sidebar inventory, `AdminModel`, the window chrome
// (publisher header + sidebar + root shell), and surfaces 1-8 (Orientation
// through Review and setup). `native/admin-support.swift` holds surfaces 9-16,
// the verify/brief plumbing, and `AdminWindowController`. Both compile into
// the same module (`swiftc native/*.swift`), so types split freely across the
// two.

import AppKit
import SwiftUI

// MARK: - Process runner (real process calls, always off the main thread)

/// Runs commands off the main thread. Admin's packaged tools are prepended to
/// PATH for every child process, so the product never depends on Homebrew or
/// the administrator's shell configuration at runtime.
enum ShellRunner {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ command: String) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-lc", command]
                process.environment = AdminPaths.childProcessEnvironment
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Output(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Output(
                    exitCode: process.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
        }
    }

    /// Executes a fixed binary with an argument array. Mutating setup uses
    /// this path so organization names and file paths never enter a shell.
    static func run(executable: String, arguments: [String]) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = AdminPaths.childProcessEnvironment
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Output(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: Output(
                    exitCode: process.terminationStatus,
                    stdout: String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    stderr: String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                ))
            }
        }
    }
}

/// Local, non-blocking-at-init file I/O. Every call here runs off the main
/// thread; callers await the result from a user-triggered `Task`.
enum AdminIO {
    static func writeFile(contents: String, to path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let url = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try contents.write(to: url, atomically: true, encoding: .utf8)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

// MARK: - Fixed paths (the seams named in admin-standup-contract.md)

enum AdminPaths {
    /// §1.1: the single, fixed, app-owned brief path. Never inside a git
    /// working tree; never timestamped, so it stays the Setup check's stable
    /// drift baseline across every re-run.
    static var briefPath: String {
        NSHomeDirectory() + "/Library/Application Support/CopilotControlTower/standup-brief.md"
    }

    /// Machine-readable twin of the operator-readable brief. The packaged
    /// app passes this file to the engine so Admin has no Python dependency.
    static var briefJSONPath: String {
        NSHomeDirectory() + "/Library/Application Support/CopilotControlTower/standup-brief.json"
    }

    /// Build and test override first, then app resources, then the unbundled
    /// development binary's sibling directory.
    static var bundledBinPath: String {
        if let override = ProcessInfo.processInfo.environment["CT_ADMIN_TOOLS_DIR"],
           !override.isEmpty {
            return override
        }
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: "bin", relativeTo: URL(fileURLWithPath: resourcePath)).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        return executableDir.appendingPathComponent("bin").path
    }

    static func bundledTool(_ name: String) -> String? {
        let candidate = URL(fileURLWithPath: name, relativeTo: URL(fileURLWithPath: bundledBinPath)).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: candidate) else { return nil }
        return candidate
    }

    static var childProcessEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existing = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(bundledBinPath):\(existing)"
        return environment
    }

    /// CONTRACT SEAM: the interim engine's path, injectable in this one place
    /// so the WS-A freeze swap to `copilot admin bootstrap --verify --json`
    /// (contract §8) only touches this constant. Resolved from the app
    /// bundle's Resources first (correct once a packaged build copies the
    /// engine script in), falling back to a working-directory-relative
    /// resolution — the same convention `AviatorGlyph`/`ControlTowerGlyph`
    /// use in `models.swift` — for today's unbundled `swiftc` dev build
    /// (`scripts/build-admin.command`), which does not yet copy any
    /// resources into a `Contents/Resources`-style directory.
    static var enginePath: String {
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: "scripts/admin_bootstrap.sh", relativeTo: URL(fileURLWithPath: resourcePath)).standardizedFileURL
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled.path
            }
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let besideBinary = executableDir.appendingPathComponent("admin_bootstrap.sh").path
        if FileManager.default.fileExists(atPath: besideBinary) {
            return besideBinary
        }
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: "scripts/admin_bootstrap.sh", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL.path
    }

    /// Display-only, abbreviated the same way the copy deck shows it
    /// (`~/…/CopilotControlTower/standup-brief.md`).
    static var briefPathDisplay: String {
        "~/…/CopilotControlTower/standup-brief.md"
    }
}

// MARK: - Slug derivation (app-side legibility only; the engine never
// silently transforms a value — see scripts/admin_bootstrap.sh's own
// `_valid_slug`/`_suggest_slug` comments. This app-side helper is what lets
// Earl type "Accounting" and see `-accounting` in the live plan card.)

enum AdminSlug {
    /// Lowercases, replaces runs of non `[a-z0-9]` with a single `-`, and
    /// trims leading/trailing dashes. Empty input (or input that carries no
    /// letters/digits at all) derives to an empty string, which the caller
    /// treats as "give this a name" refusal.
    static func derive(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        var result = ""
        var pendingDash = false
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                if pendingDash && !result.isEmpty {
                    result.append("-")
                }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result
    }

    /// GitHub's real organization-name rule, used ONLY for the org identity
    /// (never for department names, which stay app-derived slugs). Must
    /// exactly match the engine's `_valid_org` (scripts/admin_bootstrap.sh,
    /// owned by a parallel agent): ASCII letters/digits and single hyphens,
    /// no leading/trailing hyphen, no consecutive hyphens, length 1 to 39.
    /// Case is significant on GitHub (an org's slug keeps the case it was
    /// created with, e.g. `Acme-Copilot`), so this never lowercases or
    /// otherwise transforms the value it validates.
    static func isValidGitHubOrgName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 39 else { return false }
        let chars = Array(value)
        var previousWasHyphen = false
        for (index, ch) in chars.enumerated() {
            if ch == "-" {
                if index == 0 || index == chars.count - 1 || previousWasHyphen { return false }
                previousWasHyphen = true
                continue
            }
            let isAsciiLetter = ch.isASCII && ch.isLetter
            let isAsciiDigit = ch.isASCII && ch.isNumber
            guard isAsciiLetter || isAsciiDigit else { return false }
            previousWasHyphen = false
        }
        return true
    }
}

// MARK: - The one hard block reused on every field that could carry a store
// value (copy deck §3.6/3.9/3.16; interaction-design invariant #4).

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

/// A labeled field that runs the secret-shape refusal inline on every
/// keystroke: a refused value is never written into the bound `value` (not
/// stored, not logged). Copy deck §3.9/§3.16 wording, verbatim.
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

// MARK: - Small shared chrome (cards, chips, copyable code)

/// `surface.card` grouped block (visual-system §2.1), reused by every
/// onboarding surface's teach/plan/enumeration blocks.
struct AdminCard<Content: View>: View {
    var title: String? = nil
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .textCase(.uppercase)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// `surface.field` mono block (visual-system §2.1: "code / handoff blocks"),
/// with a Copy affordance that reads "Copied" for ~2s, never a toast.
struct CopyableCodeBlock: View {
    let text: String
    var copyLabel: String = "Copy"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(Color(nsColor: .labelColor))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Text(copied ? "Copied" : copyLabel)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(copyLabel)
        }
    }
}

/// The plain owner tag (`Admin` / `GitHub org owner` / `IT infra` /
/// `The foundation (external)`), radius-6 chip, per visual-system §6.8.
struct OwnerChip: View {
    let owner: String

    var body: some View {
        Text(owner)
            .font(.caption.weight(.semibold))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .separatorColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Sidebar inventory (interaction-design §1, copy deck §3.2)

enum AdminOnboardingStage: Int, CaseIterable, Identifiable {
    case orientation, prerequisites, contacts, connectGitHub, describeOrg
    case integrations, secretStore, review, handedOff, setupCheck, done
    var id: Int { rawValue }

    var sidebarLabel: String {
        switch self {
        case .orientation: return "Orientation"
        case .prerequisites: return "Prerequisites"
        case .contacts: return "Contacts"
        case .connectGitHub: return "Connect GitHub"
        case .describeOrg: return "Describe your organization"
        case .integrations: return "Integrations"
        case .secretStore: return "Secret store"
        case .review: return "Review setup"
        case .handedOff: return "Organization setup"
        case .setupCheck: return "Setup check"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .orientation: return "map"
        case .prerequisites: return "checklist"
        case .contacts: return "person.text.rectangle"
        case .connectGitHub: return "point.3.connected.trianglepath.dotted"
        case .describeOrg: return "building.2"
        case .integrations: return "puzzlepiece.extension"
        case .secretStore: return "lock.doc"
        case .review: return "arrow.left.arrow.right.circle"
        case .handedOff: return "checkmark.seal"
        case .setupCheck: return "checklist.checked"
        case .done: return "checkmark.seal"
        }
    }
}

enum AdminGovernanceStage: Int, CaseIterable, Identifiable {
    case addDepartment, someoneLeft, connectStore, orgSetup, analytics
    var id: Int { rawValue }

    var sidebarLabel: String {
        switch self {
        case .addDepartment: return "Add a department"
        case .someoneLeft: return "Someone left"
        case .connectStore: return "Connect the shared store"
        case .orgSetup: return "Org setup"
        case .analytics: return "Analytics"
        }
    }

    var icon: String {
        switch self {
        case .addDepartment: return "person.badge.plus"
        case .someoneLeft: return "person.badge.minus"
        case .connectStore: return "key.viewfinder"
        case .orgSetup: return "list.bullet.rectangle"
        case .analytics: return "chart.bar.doc.horizontal"
        }
    }
}

enum AdminSelection: Hashable {
    case onboarding(AdminOnboardingStage)
    case governance(AdminGovernanceStage)
}

/// The roadmap grammar (interaction-design §1.3): done / current / upcoming,
/// plus the one new advisory token (partial + count) for Connect GitHub.
enum AdminProgressMark: Equatable {
    case done
    case current
    case upcoming
    case partial(done: Int, total: Int)
}

// MARK: - Domain types

enum Harness: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
    /// The `<harness>-copilot*` naming token the plan card and the brief both
    /// use (admin-standup-contract.md §1.3/§4).
    var repoToken: String { rawValue }
}

struct DepartmentEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var slug: String { AdminSlug.derive(name) }
}

enum StoreConnectionStatus: Equatable {
    case undecided
    case connected
    case deferred
}

enum StoreKind: String, CaseIterable, Identifiable {
    case onePassword = "1Password"
    case infisical = "Infisical"
    case vault = "Vault"
    var id: String { rawValue }
}

/// Readiness rows for the self-contained Admin app. Local tools ship inside
/// the app; GitHub identity, scopes, and organization ownership are read from
/// GitHub through the bundled CLI.
enum ReadinessStatus: Equatable {
    case notChecked
    case checking
    case pass
    case fail
    case cannotCheckLocally
}

struct ReadinessRow: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case adminTools, signedIn, owner, scopes
        var id: String { rawValue }
    }

    var id: Kind { kind }
    let kind: Kind
    var status: ReadinessStatus = .notChecked
    var detail: String = ""

    func baseTitle(org: String) -> String {
        switch kind {
        case .adminTools: return "Admin tools are included"
        case .signedIn: return "GitHub account"
        case .owner: return "Your account is an owner of \(org.isEmpty ? "your organization" : org)"
        case .scopes: return "Setup permission"
        }
    }
}

extension Array where Element == ReadinessRow {
    subscript(kind: ReadinessRow.Kind) -> ReadinessRow {
        get { first(where: { $0.kind == kind }) ?? ReadinessRow(kind: kind) }
        set {
            if let idx = firstIndex(where: { $0.kind == kind }) {
                self[idx] = newValue
            }
        }
    }
}

/// The verify verb's row shape (admin-standup-contract.md §3.1), rendered,
/// never computed, by the Setup check (`native/admin-support.swift`).
struct VerifyRow: Identifiable {
    let id = UUID()
    let check: String
    let status: String
    let detail: String
    let owner: String
    let fixSurface: String
}

enum WriteState: Equatable {
    case idle
    case working
    case success
    case failure
}

// MARK: - AdminModel

@MainActor
final class AdminModel: ObservableObject {
    // Navigation
    @Published var selection: AdminSelection = .onboarding(.orientation)
    @Published var completedOnboarding: Set<AdminOnboardingStage> = []

    static let onboardingOrder: [AdminOnboardingStage] = AdminOnboardingStage.allCases

    // Surface 1: Orientation
    @Published var showingLearnMore = false
    @Published var learnMorePage = 0
    @Published var handoffReadable = false // CONTRACT SEAM: see admin-support.swift's handoffHeader

    // Surface 3: Contacts
    @Published var contactPublisher = ""
    @Published var contactAdmin = ""
    @Published var contactPointOfContact = ""
    @Published var contactsSaved = false

    // Surface 4: Connect GitHub (shared org identity with Describe, below)
    @Published var orgNameInput = ""
    @Published var githubOAuthClientIDInput = ""
    @Published var githubOAuthClientIDTouched = false
    @Published var githubOAuthClientIDRefused = false
    @Published var readinessRows: [ReadinessRow] = ReadinessRow.Kind.allCases.map { ReadinessRow(kind: $0) }
    @Published var githubChecking = false
    @Published var githubAuthorizing = false
    @Published var githubAuthorizationMessage: String? = nil
    @Published var githubCheckDegraded = false
    private var readinessDebounceTask: Task<Void, Never>? = nil

    /// The org identity is an EXISTING GitHub organization name, not a value
    /// this app derives or slugifies: it is used verbatim (trimmed of
    /// surrounding whitespace only), case preserved, so an org actually
    /// named `Acme-Copilot` is never silently lowercased to `acme-copilot`
    /// in the plan card, the brief, or the Setup check. Departments stay
    /// app-derived slugs (`AdminSlug.derive`), unchanged, since their repo
    /// names are generated, not an existing identifier.
    var orgSlug: String { orgNameInput.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// GitHub OAuth client IDs are public identifiers. GitHub has issued more
    /// than one prefix over time, so validate the stable contract instead of
    /// hard-coding one generation: exactly 20 ASCII letters, digits, or dots.
    var githubOAuthClientID: String {
        githubOAuthClientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var githubOAuthClientIDIsValid: Bool {
        githubOAuthClientID.range(
            of: #"^[A-Za-z0-9.]{20}$"#,
            options: .regularExpression
        ) != nil
    }

    // Surface 5: Describe your organization
    @Published var harness: Harness = .codex
    @Published var departments: [DepartmentEntry] = []
    @Published var orgSlugTouched = false

    // Surface 7: Secret store
    @Published var storeKind: StoreKind = .infisical
    @Published var storeAddress = ""
    @Published var storeWorkspaceID = ""
    @Published var storeEnvironment = "prod"
    @Published var storeSecretPath = "/shared"
    @Published var storeAddressTouchedInvalid = false
    @Published var storeScopeByDepartment: [UUID: String] = [:]
    @Published var storeStatus: StoreConnectionStatus = .undecided

    // Surface 8: Review and hand off. `lastWrittenBriefFingerprint` (not a
    // one-shot "already generated" flag) is what gates re-writing the brief:
    // going Back from Review, editing any brief-feeding input, and returning
    // must rewrite the brief and re-gate the command block (QA fix), while
    // simply re-visiting Review without changing anything must not spuriously
    // rewrite. See `AdminModel.briefFingerprint` in native/admin-support.swift.
    @Published var briefWriteState: WriteState = .idle
    @Published var lastWrittenBriefFingerprint: String? = nil
    @Published var repositoryPlanState: WriteState = .idle
    @Published var repositoryPlan: OnboardReport? = nil
    @Published var repositoryApplyState: WriteState = .idle
    @Published var repositorySetupMessage: String? = nil

    // Surface 10: Setup check
    @Published var verifyState: WriteState = .idle // idle == never run
    @Published var verifyRows: [VerifyRow] = []
    @Published var verifyMustFix = 0
    @Published var verifyUnknown = 0
    @Published var verifyDegradedLine: String? = nil

    // Surface 16: Analytics
    @Published var analyticsEnabled = false

    // Governance: Someone left (CONTRACT SEAM: no real lookup, see
    // native/admin-support.swift's someoneLeftView)
    @Published var someoneLeftLookup = ""
    @Published var someoneLeftLookedUp = false

    // MARK: Navigation helpers

    func markComplete(_ stage: AdminOnboardingStage) {
        completedOnboarding.insert(stage)
    }

    func advance(from stage: AdminOnboardingStage) {
        markComplete(stage)
        guard let idx = Self.onboardingOrder.firstIndex(of: stage), idx + 1 < Self.onboardingOrder.count else { return }
        selection = .onboarding(Self.onboardingOrder[idx + 1])
    }

    func goBack(from stage: AdminOnboardingStage) {
        guard let idx = Self.onboardingOrder.firstIndex(of: stage), idx > 0 else { return }
        selection = .onboarding(Self.onboardingOrder[idx - 1])
    }

    func progressMark(for stage: AdminOnboardingStage) -> AdminProgressMark {
        if case .onboarding(let current) = selection, current == stage { return .current }
        if stage == .connectGitHub {
            let passCount = readinessRows.filter { $0.status == .pass }.count
            if passCount == readinessRows.count { return .done }
            return .partial(done: passCount, total: readinessRows.count)
        }
        return completedOnboarding.contains(stage) ? .done : .upcoming
    }

    // MARK: Contacts

    func saveContacts() {
        contactsSaved = true
        advance(from: .contacts)
    }

    // MARK: Connect GitHub

    func checkGitHubReadiness() {
        Task { await runGitHubReadinessCheck() }
    }

    func scheduleGitHubReadinessCheck() {
        readinessDebounceTask?.cancel()
        guard orgSlugIsValid else {
            var owner = readinessRows[.owner]
            owner.status = .cannotCheckLocally
            owner.detail = "Enter the existing GitHub organization name so Admin can verify ownership."
            readinessRows[.owner] = owner
            return
        }
        readinessDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await runGitHubReadinessCheck()
        }
    }

    func runGitHubReadinessCheck() async {
        githubChecking = true
        githubCheckDegraded = false
        githubAuthorizationMessage = nil
        for i in readinessRows.indices { readinessRows[i].status = .checking }

        guard let ghPath = AdminPaths.bundledTool("gh"),
              let jqPath = AdminPaths.bundledTool("jq")
        else {
            var row = readinessRows[.adminTools]
            row.status = .fail
            row.detail = "This Admin app is incomplete. Download or rebuild the complete app before continuing."
            readinessRows[.adminTools] = row
            for kind in [ReadinessRow.Kind.signedIn, .owner, .scopes] {
                var dependent = readinessRows[kind]
                dependent.status = .cannotCheckLocally
                dependent.detail = "Waiting for the complete Admin app."
                readinessRows[kind] = dependent
            }
            githubCheckDegraded = true
            githubChecking = false
            return
        }

        async let ghVersionAsync = ShellRunner.run(executable: ghPath, arguments: ["--version"])
        async let jqVersionAsync = ShellRunner.run(executable: jqPath, arguments: ["--version"])
        let ghVersion = await ghVersionAsync
        let jqVersion = await jqVersionAsync
        let toolsReady = ghVersion.exitCode == 0 && jqVersion.exitCode == 0

        var toolsRow = readinessRows[.adminTools]
        if toolsReady {
            toolsRow.status = .pass
            toolsRow.detail = "Everything Admin needs locally is inside this app."
        } else {
            toolsRow.status = .fail
            toolsRow.detail = "The tools inside this Admin app did not start correctly. Download or rebuild the complete app."
            githubCheckDegraded = true
        }
        readinessRows[.adminTools] = toolsRow

        guard toolsReady else {
            for kind in [ReadinessRow.Kind.signedIn, .owner, .scopes] {
                var dependent = readinessRows[kind]
                dependent.status = .cannotCheckLocally
                dependent.detail = "Waiting for the complete Admin app."
                readinessRows[kind] = dependent
            }
            githubChecking = false
            return
        }

        let auth = await ShellRunner.run(
            executable: ghPath,
            arguments: ["auth", "status", "--active", "--hostname", "github.com", "--json", "hosts"]
        )
        let account = Self.activeGitHubAccount(from: auth.stdout)

        var signedInRow = readinessRows[.signedIn]
        if let account, account.state == "success", !account.login.isEmpty {
            signedInRow.status = .pass
            signedInRow.detail = "Connected as \(account.login)."
        } else {
            signedInRow.status = .fail
            signedInRow.detail = "This Mac is not connected to GitHub yet."
        }
        readinessRows[.signedIn] = signedInRow

        var scopesRow = readinessRows[.scopes]
        if let account, account.state == "success" {
            let scopes = Set(account.scopes.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            if scopes.contains("admin:org") && scopes.contains("repo") {
                scopesRow.status = .pass
                scopesRow.detail = "GitHub has granted the access organization setup needs."
            } else {
                scopesRow.status = .fail
                scopesRow.detail = "GitHub still needs your approval to create and configure private organization spaces."
            }
        } else {
            scopesRow.status = .cannotCheckLocally
            scopesRow.detail = "Checked after GitHub authorization."
        }
        readinessRows[.scopes] = scopesRow

        var ownerRow = readinessRows[.owner]
        guard let account, account.state == "success" else {
            ownerRow.status = .cannotCheckLocally
            ownerRow.detail = "Checked after GitHub authorization."
            readinessRows[.owner] = ownerRow
            githubChecking = false
            return
        }
        guard orgSlugIsValid else {
            ownerRow.status = .cannotCheckLocally
            ownerRow.detail = "Enter the existing GitHub organization name so Admin can verify ownership."
            readinessRows[.owner] = ownerRow
            githubChecking = false
            return
        }

        let membership = await ShellRunner.run(
            executable: ghPath,
            arguments: [
                "api",
                "orgs/\(orgSlug)/memberships/\(account.login)",
                "--jq",
                ".role + \":\" + .state",
            ]
        )
        let membershipState = membership.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if membership.exitCode == 0 && membershipState == "admin:active" {
            ownerRow.status = .pass
            ownerRow.detail = "GitHub confirms this account is an active owner."
        } else {
            ownerRow.status = .fail
            ownerRow.detail = "GitHub does not report this account as an active owner of \(orgSlug). An existing owner must grant that role."
        }
        readinessRows[.owner] = ownerRow
        githubChecking = false
    }

    private struct GitHubAccount {
        let login: String
        let state: String
        let scopes: String
    }

    private static func activeGitHubAccount(from json: String) -> GitHubAccount? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hosts = root["hosts"] as? [String: Any],
              let accounts = hosts["github.com"] as? [[String: Any]],
              let account = accounts.first(where: { ($0["active"] as? Bool) == true }),
              let login = account["login"] as? String,
              let state = account["state"] as? String
        else { return nil }
        return GitHubAccount(
            login: login,
            state: state,
            scopes: account["scopes"] as? String ?? ""
        )
    }

    var githubNeedsAuthorization: Bool {
        readinessRows[.signedIn].status == .fail || readinessRows[.scopes].status == .fail
    }

    var githubReadinessComplete: Bool {
        ReadinessRow.Kind.allCases.allSatisfy { readinessRows[$0].status == .pass }
    }

    var canContinueFromGitHub: Bool {
        githubReadinessComplete && githubOAuthClientIDIsValid
    }

    func authorizeGitHub() {
        guard !githubAuthorizing, let ghPath = AdminPaths.bundledTool("gh") else { return }
        githubAuthorizing = true
        githubAuthorizationMessage = "Finish authorizing in the GitHub browser window. Admin will check again when it closes."
        Task {
            let signedIn = readinessRows[.signedIn].status == .pass
            let arguments: [String]
            if signedIn {
                arguments = [
                    "auth", "refresh",
                    "--hostname", "github.com",
                    "--clipboard",
                    "--scopes", "repo,read:org,admin:org",
                ]
            } else {
                arguments = [
                    "auth", "login",
                    "--hostname", "github.com",
                    "--git-protocol", "https",
                    "--web",
                    "--clipboard",
                    "--scopes", "repo,read:org,admin:org",
                    "--skip-ssh-key",
                ]
            }
            let result = await ShellRunner.run(executable: ghPath, arguments: arguments)
            githubAuthorizing = false
            await runGitHubReadinessCheck()
            if result.exitCode != 0 {
                githubAuthorizationMessage = "GitHub authorization did not finish. Nothing was changed; try again when you're ready."
            }
        }
    }

    func openOrganizationSettings() {
        guard orgSlugIsValid,
              let url = URL(string: "https://github.com/organizations/\(orgSlug)/settings/profile")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func openOAuthAppSettings() {
        let path = orgSlugIsValid
            ? "https://github.com/organizations/\(orgSlug)/settings/applications"
            : "https://github.com/settings/developers"
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
    }

    func advanceFromGitHub() {
        guard canContinueFromGitHub else { return }
        advance(from: .connectGitHub)
    }

    // MARK: Describe your organization

    func addDepartment() {
        departments.append(DepartmentEntry())
    }

    func removeDepartment(_ id: UUID) {
        departments.removeAll { $0.id == id }
        storeScopeByDepartment.removeValue(forKey: id)
    }

    var orgSlugIsValid: Bool { AdminSlug.isValidGitHubOrgName(orgSlug) }

    /// The live "What this will create" plan card content, derived (never
    /// computed as ecosystem state — this is legibility only; the engine is
    /// the authority that actually creates anything). Copy deck §3.7.
    var planCardLines: [String] {
        guard orgSlugIsValid else { return [] }
        var lines: [String] = []
        let org = orgSlug
        lines.append("Four private shared spaces for your whole organization:")
        for component in ["knowledge", "cli", "claude", "codex"] {
            lines.append("\(org)/\(component)-copilot-internal")
        }
        for dept in departments where !dept.slug.isEmpty {
            let display = dept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("")
            lines.append("Four private spaces for the \(display) department:")
            for component in ["knowledge", "cli", "claude", "codex"] {
                lines.append("\(org)/\(component)-copilot-\(dept.slug)")
            }
            // Rephrased to avoid an a/an article choice on an arbitrary typed
            // name (QA fix: "an Sales team" mis-articled a consonant name).
            lines.append("A team for \(display) that can reach them.")
        }
        lines.append("")
        lines.append("Your whole organization set to read by default.")
        return lines
    }

    // MARK: Secret store

    func scopeBinding(for dept: DepartmentEntry) -> Binding<String> {
        Binding(
            get: { self.storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)" },
            set: { self.storeScopeByDepartment[dept.id] = $0 }
        )
    }

    var storeAddressLooksValid: Bool {
        storeAddress.isEmpty || SecretShapeCheck.looksLikeURL(storeAddress)
    }

    func finishSecretStore(connect: Bool) {
        if connect, !storeAddress.isEmpty, SecretShapeCheck.looksLikeURL(storeAddress), storeConnectionDetailsAreValid {
            storeStatus = .connected
        } else if !connect {
            storeStatus = .deferred
        } else if storeAddress.isEmpty {
            storeStatus = .deferred
        }
        advance(from: .secretStore)
    }

    var storeAtAGlance: String {
        switch storeStatus {
        case .connected: return "store connected"
        case .deferred, .undecided: return "store not connected yet"
        }
    }

    var storeConnectionDetailsAreValid: Bool {
        guard storeKind == .infisical else { return true }
        return !storeWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !storeEnvironment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && storeSecretPath.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    /// The `store.type` slug `buildBriefContents()` (native/admin-support.swift)
    /// writes to the brief. Shared (not `private`) so both files can use the
    /// one mapping instead of drifting duplicates.
    var storeKindSlug: String {
        switch storeKind {
        case .onePassword: return "1password"
        case .infisical: return "infisical"
        case .vault: return "vault"
        }
    }

    /// Every valid (non-empty-slug) department, the shape both the plan card
    /// and the brief writer iterate over.
    var validDepartments: [DepartmentEntry] {
        departments.filter { !$0.slug.isEmpty }
    }

    /// A cheap, order-stable fingerprint of every field that feeds
    /// `buildBriefContents()`, contacts included. Compared against
    /// `lastWrittenBriefFingerprint` to decide whether Review needs to
    /// rewrite the brief (QA fix: a stale fingerprint used to let Back +
    /// edit + return show an out-of-date command).
    var briefFingerprint: String {
        var parts: [String] = [orgSlug, githubOAuthClientID, harness.rawValue]
        parts.append(contentsOf: validDepartments.map { $0.slug })
        switch storeStatus {
        case .connected:
            parts.append("connected")
            parts.append(storeKindSlug)
            parts.append(storeAddress)
            parts.append(storeWorkspaceID)
            parts.append(storeEnvironment)
            parts.append(storeSecretPath)
            for dept in validDepartments {
                parts.append(storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)")
            }
        case .deferred, .undecided:
            parts.append("deferred")
        }
        parts.append(contactPublisher)
        parts.append(contactAdmin)
        parts.append(contactPointOfContact)
        return parts.joined(separator: "\u{1}")
    }
}

// MARK: - Window chrome: handoff header + two-section sidebar + root shell

/// Persistent, read-only banner atop the window whenever an Onboarding item
/// is selected (interaction-design §1.1; copy deck §3.1). CONTRACT SEAM: the
/// Publisher-to-Admin handoff object has no frozen schema anywhere in this
/// repo yet (no `docs/01-architecture/schemas/*handoff*`), so this always
/// renders the honest "can't read it" state rather than a fabricated one —
/// exactly the degraded state the design itself specifies for this case.
struct AdminHandoffHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .accessibilityHidden(true)
            Text("Not started yet")
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Handoff status: not started yet")
    }
}

struct AdminSidebar: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        List(selection: Binding(
            get: { model.selection },
            set: { if let newValue = $0 { model.selection = newValue } }
        )) {
            Section("ONBOARDING") {
                ForEach(AdminOnboardingStage.allCases) { stage in
                    row(label: stage.sidebarLabel, icon: stage.icon, mark: model.progressMark(for: stage))
                        .tag(AdminSelection.onboarding(stage))
                }
            }
            Section("GOVERNANCE") {
                ForEach(AdminGovernanceStage.allCases) { stage in
                    row(label: stage.sidebarLabel, icon: stage.icon, mark: nil)
                        .tag(AdminSelection.governance(stage))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(label: String, icon: String, mark: AdminProgressMark?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer()
            if let mark {
                markView(mark)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(label)\(mark.map { ", " + accessibilityWord($0) } ?? "")")
    }

    @ViewBuilder
    private func markView(_ mark: AdminProgressMark) -> some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: .systemGreen))
        case .current:
            Image(systemName: "circle.inset.filled")
                .foregroundColor(Color(nsColor: .controlAccentColor))
        case .upcoming:
            Image(systemName: "circle")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .partial(let done, let total):
            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                Text("\(done)/\(total)")
                    .font(.caption)
            }
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    private func accessibilityWord(_ mark: AdminProgressMark) -> String {
        switch mark {
        case .done: return "done"
        case .current: return "current"
        case .upcoming: return "upcoming"
        case .partial(let done, let total): return "\(done) of \(total) ready"
        }
    }
}

struct AdminRootView: View {
    @ObservedObject var model: AdminModel

    var body: some View {
        NavigationSplitView {
            AdminSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if isOnboardingSelected {
                    AdminHandoffHeader()
                }
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, idealWidth: 1080, minHeight: 680, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var isOnboardingSelected: Bool {
        if case .onboarding = model.selection { return true }
        return false
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .onboarding(let stage):
            onboardingDetail(stage)
        case .governance(let stage):
            governanceDetail(stage)
        }
    }

    @ViewBuilder
    private func onboardingDetail(_ stage: AdminOnboardingStage) -> some View {
        switch stage {
        case .orientation: orientationView
        case .prerequisites: prerequisitesView
        case .contacts: contactsView
        case .connectGitHub: connectGitHubView
        case .describeOrg: describeOrgView
        case .integrations: integrationsView
        case .secretStore: secretStoreView
        case .review: reviewView
        case .handedOff: handedOffView
        case .setupCheck: setupCheckView
        case .done: doneView
        }
    }

    @ViewBuilder
    private func governanceDetail(_ stage: AdminGovernanceStage) -> some View {
        switch stage {
        case .addDepartment: addDepartmentView
        case .someoneLeft: someoneLeftView
        case .connectStore: connectStoreGovernanceView
        case .orgSetup: orgSetupView
        case .analytics: analyticsView
        }
    }

    // MARK: Shared footer buttons

    func backButton(_ action: @escaping () -> Void) -> some View {
        Button { action() } label: { Text("Back") }
            .buttonStyle(.bordered)
    }

    func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button { action() } label: { Text(title) }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }
}

// MARK: - Surface 1: Orientation

extension AdminRootView {
    var orientationView: some View {
        Group {
            if model.showingLearnMore {
                learnMoreView
            } else {
                orientationMainView
            }
        }
    }

    private var orientationMainView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Here's what you're building, and the whole path",
            intro: "Your copilots live in a set of shared spaces on GitHub that build on one another. The open-source foundation sits at the bottom. Your organization adds its own on top. Each department adds what only it needs. Each person adds their own on top of that. Everyone inherits everything beneath them, so you share broad capabilities widely and keep specialized ones narrow."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AdminCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Describe your organization here.")
                        Text("2. Review exactly what Admin found and will create.")
                        Text("3. Let Admin set it up and verify the result.")
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                }

                Text("Admin checks GitHub first, reuses what is already safe, creates only confirmed-missing private spaces, and verifies the result.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.showingLearnMore = true
                    model.learnMorePage = 0
                } label: {
                    Text("Learn how the ecosystem works ›")
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .controlAccentColor))
                .accessibilityLabel("Learn how the ecosystem works, opens an explainer")
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            primaryButton("Start") {
                model.advance(from: .orientation)
            }
        }
    }

    var learnMoreView: some View {
        StepShell(
            eyebrow: "LEARN MORE",
            title: model.learnMorePage == 0 ? "How it works" : "What your team gets",
            intro: nil
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Picker("", selection: $model.learnMorePage) {
                    Text("How it works").tag(0)
                    Text("What your team gets").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                EcosystemDiagram()
                    .frame(maxWidth: 480)
                    .accessibilityLabel("The four layers, each inheriting everything beneath it: the open-source foundation, then your organization, then each department, then each person.")

                if model.learnMorePage == 0 {
                    Text("Each layer carries three kinds of space: one for instructions and agents (your harness's copilot), one for knowledge (your company's information), and one for integrations (tools that reach outside systems). The org level carries org-level agents, org-level integrations, and org information.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Every person inherits your organization's agents, skills, knowledge, and integrations, plus their department's, on the open-source foundation. They build their own solutions faster, going broad with what the org shares and narrow with what their department adds.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    AdminCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Org: a skill that writes on-brand documents in your brand voice, and a proposal and SOW builder.")
                            Text("Accounting: a month-end reconciliation skill.")
                            Text("IT: an onboarding and offboarding access-runbook skill.")
                            Text("Sales: a call-prep brief skill.")
                        }
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        } leadingActions: {
            Button {
                model.showingLearnMore = false
            } label: {
                Text("‹ Back to the overview")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            EmptyView()
        }
    }
}

/// A theme-aware, native (never raster) rendering of the four inheriting
/// layers (interaction-design Surface 1's "Learn more" diagram). Colors are
/// all dynamic `NSColor`s, so light/dark redraw is instant and automatic.
struct EcosystemDiagram: View {
    private let rows: [(title: String, subtitle: String)] = [
        ("Personal", "this Mac"),
        ("Department", "e.g. Accounting"),
        ("Organization", "your company"),
        ("Foundation", "open source"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                layerRow(row.title, subtitle: row.subtitle, isTop: index == 0)
                if index < rows.count - 1 {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        Text("inherits")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func layerRow(_ title: String, subtitle: String, isTop: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Surface 2: Prerequisites

extension AdminRootView {
    var prerequisitesView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Before you begin",
            intro: "Admin includes the local tools it needs and checks them for you. You only provide organization decisions and approve GitHub access."
        ) {
            AdminCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your organization exists on GitHub. Creating one needs billing and a person, so it can't be automated. If it doesn't exist yet, create it at github.com first.")
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://github.com/account/organizations/new")!)
                            } label: {
                                Text("Open github ›")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .controlAccentColor))
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("You are an owner of it. Only an owner can create the organization's spaces.")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("The next step checks this Mac, your GitHub sign-in, organization ownership, and setup permission automatically. If GitHub needs your approval, one button opens its browser authorization.")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("Review protection needs a paid GitHub plan. Setup asks GitHub to require a review before your shared setup files change. For private repositories, GitHub only offers that on a paid plan. On the free plan, setup still finishes and your spaces are created, they just won't have review protection until you upgrade.")
                    }
                }
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
                .fixedSize(horizontal: false, vertical: true)
            }
        } leadingActions: {
            backButton { model.goBack(from: .prerequisites) }
        } primaryAction: {
            primaryButton("Continue") { model.advance(from: .prerequisites) }
        }
    }
}

// MARK: - Surface 3: Contacts

extension AdminRootView {
    var contactsView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Who's who",
            intro: "Record who owns this setup, so the handoff is never guesswork. These names show in the handoff banner and in the setup check."
        ) {
            AdminCard {
                VStack(alignment: .leading, spacing: 14) {
                    labeledField("Publisher", text: $model.contactPublisher)
                    labeledField("Admin", text: $model.contactAdmin)
                    labeledField("Point of contact", text: $model.contactPointOfContact)
                }
            }
        } leadingActions: {
            backButton { model.goBack(from: .contacts) }
            if model.contactsSaved {
                Text("Saved.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } primaryAction: {
            primaryButton("Continue") { model.saveContacts() }
        }
    }

    // Contacts feed `buildBriefContents()`'s `contacts:` block verbatim (as
    // quoted YAML strings), so they run the same secret-shape refusal as the
    // store fields (QA fix: every free-text field bound into the brief must
    // be guarded, not just the two store-collecting surfaces).
    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            SecretGuardedField(label: "", value: text)
        }
    }
}

// MARK: - Surface 4: Connect GitHub

extension AdminRootView {
    var connectGitHubView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Get this Mac ready",
            intro: "Admin includes the local tools it needs. It checks GitHub access and your organization automatically, then asks only for approvals GitHub requires from you."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    SecretGuardedField(label: "", value: $model.orgNameInput, placeholder: "acme-co")
                        .frame(maxWidth: 320)
                        .onChange(of: model.orgNameInput) { _ in
                            model.orgSlugTouched = true
                            model.scheduleGitHubReadinessCheck()
                        }
                    if model.orgSlugTouched, !model.orgNameInput.isEmpty, !model.orgSlugIsValid {
                        Text("Use the organization's exact GitHub name.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemRed))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub OAuth App client ID")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    // A GitHub OAuth Client ID intentionally looks like a
                    // high-entropy token, but it is public configuration.
                    // This dedicated field validates the exact public shape;
                    // a client secret is longer and cannot pass that gate.
                    TextField(
                        "Iv1.a1b2c3d4e5f6a7b8",
                        text: Binding(
                            get: { model.githubOAuthClientIDInput },
                            set: { newValue in
                                model.githubOAuthClientIDTouched = true
                                if newValue.count <= 20 {
                                    model.githubOAuthClientIDRefused = false
                                    model.githubOAuthClientIDInput = newValue
                                } else {
                                    model.githubOAuthClientIDRefused = true
                                }
                            }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    Text("Paste the public Client ID from your organization's device-flow-enabled GitHub OAuth App. Never paste its client secret.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open OAuth App settings") {
                        model.openOAuthAppSettings()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.orgSlugIsValid)
                    if model.githubOAuthClientIDRefused {
                        Text("That is not a public Client ID, so it was not accepted. Never paste the OAuth client secret here.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemRed))
                    } else if model.githubOAuthClientIDTouched,
                       !model.githubOAuthClientIDInput.isEmpty,
                       !model.githubOAuthClientIDIsValid {
                        Text("That doesn't look like a GitHub OAuth client ID. Copy the 20-character public Client ID from the OAuth App settings.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemRed))
                    }
                }

                AdminCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ReadinessRow.Kind.allCases) { kind in
                            readinessRow(model.readinessRows[kind])
                            if kind != ReadinessRow.Kind.allCases.last {
                                Divider()
                            }
                        }
                    }
                }

                if let message = model.githubAuthorizationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .accessibilityAddTraits(.updatesFrequently)
                } else if model.canContinueFromGitHub {
                    Text("Everything required on this Mac and GitHub is ready.")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                }
            }
        } leadingActions: {
            backButton { model.goBack(from: .connectGitHub) }
            if model.githubChecking || model.githubAuthorizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.githubAuthorizing ? "Waiting for GitHub authorization..." : "Checking your GitHub access...")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        } primaryAction: {
            if model.githubAuthorizing || model.githubChecking {
                primaryButton("Checking…", enabled: false) {}
            } else if model.githubNeedsAuthorization {
                primaryButton("Authorize GitHub") {
                    model.authorizeGitHub()
                }
            } else if model.canContinueFromGitHub {
                primaryButton("Continue") {
                    model.advanceFromGitHub()
                }
            } else {
                primaryButton("Check again", enabled: model.orgSlugIsValid) {
                    model.checkGitHubReadiness()
                }
            }
        }
        .task {
            if model.readinessRows.allSatisfy({ $0.status == .notChecked }) {
                model.checkGitHubReadiness()
            }
        }
    }

    private func readinessRow(_ row: ReadinessRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                readinessGlyph(row.status)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.baseTitle(org: model.orgSlug))
                        .font(.body)
                        .foregroundColor(Color(nsColor: .labelColor))
                    if row.status == .fail || row.status == .cannotCheckLocally, !row.detail.isEmpty {
                        Text(row.detail)
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if row.kind == .owner, row.status == .fail {
                        Button("Open organization settings") {
                            model.openOrganizationSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.baseTitle(org: model.orgSlug)), \(accessibilityWord(row.status))\(row.detail.isEmpty ? "" : ", " + row.detail)")
    }

    private func readinessGlyph(_ status: ReadinessStatus) -> some View {
        Group {
            switch status {
            case .notChecked:
                Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor))
            case .checking:
                ProgressView().controlSize(.small)
            case .pass:
                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(nsColor: .systemGreen))
            case .fail:
                Image(systemName: "xmark.circle.fill").foregroundColor(Color(nsColor: .systemRed))
            case .cannotCheckLocally:
                Image(systemName: "questionmark.circle").foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        .accessibilityHidden(true)
    }

    private func accessibilityWord(_ status: ReadinessStatus) -> String {
        switch status {
        case .notChecked: return "not checked yet"
        case .checking: return "checking"
        case .pass: return "ready"
        case .fail: return "not ready"
        case .cannotCheckLocally: return "can't be checked from here"
        }
    }
}

// MARK: - Surface 5: Describe your organization

extension AdminRootView {
    var describeOrgView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Describe your organization",
            intro: "Tell setup your organization's name, the harness it builds with, and its departments. As you type, you'll see exactly what will be created. Nothing is created here. This is the plan setup will follow."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Departments get their own spaces so specialized capabilities are tailored to how that department works. Accounting's spaces hold Accounting's skills and knowledge, and each department's people inherit the whole organization's on top.")
                        Text("You don't have to add every department now. Adding one later is safe. Setting up again only adds what's new and never touches what's already there.")
                            .font(.body.weight(.medium))
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Which development harness does your company build with?")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Picker("", selection: $model.harness) {
                        ForEach(Harness.allCases) { h in
                            Text(h.displayName).tag(h)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .accessibilityLabel("Development harness, \(model.harness.displayName) selected, your organization's default")

                    Text("This chooses the default experience. Setup provisions both Claude and Codex organization layers, plus Knowledge and CLI, so either harness is ready without another repository pass.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization name")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    SecretGuardedField(label: "", value: $model.orgNameInput, placeholder: "acme-co")
                        .frame(maxWidth: 320)
                        .onChange(of: model.orgNameInput) { model.orgSlugTouched = true }
                    if model.orgSlugTouched, !model.orgNameInput.isEmpty, !model.orgSlugIsValid {
                        Text("That doesn't look like a GitHub organization name. Use letters, numbers, and single dashes.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemRed))
                    }
                }

                departmentsEditor

                planCard
            }
        } leadingActions: {
            backButton { model.goBack(from: .describeOrg) }
        } primaryAction: {
            primaryButton("Continue", enabled: model.orgSlugIsValid) {
                model.advance(from: .describeOrg)
            }
        }
    }

    private var departmentsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Departments")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            ForEach(model.departments.indices, id: \.self) { idx in
                HStack(spacing: 8) {
                    SecretGuardedField(
                        label: "",
                        value: Binding(
                            get: { model.departments[idx].name },
                            set: { model.departments[idx].name = $0 }
                        ),
                        placeholder: "e.g. Accounting"
                    )
                    .frame(maxWidth: 260)

                    if !model.departments[idx].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && model.departments[idx].slug.isEmpty {
                        Text("Give this department a name using letters, numbers, and dashes.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .systemRed))
                    }

                    Button {
                        model.removeDepartment(model.departments[idx].id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .accessibilityLabel("Remove department")
                }
            }
            Button {
                model.addDepartment()
            } label: {
                Label("Add a department", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .controlAccentColor))
        }
    }

    private var planCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing is created here. This is the plan setup will follow.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(Color(nsColor: .labelColor))

                if model.orgSlugIsValid {
                    ForEach(Array(model.planCardLines.enumerated()), id: \.offset) { _, line in
                        if line.isEmpty {
                            Spacer().frame(height: 6)
                        } else if line.hasPrefix("Three ") || line.hasPrefix("Your whole organization") || line.hasPrefix("An ") {
                            Text(line)
                                .font(.body)
                                .foregroundColor(Color(nsColor: .labelColor))
                        } else {
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                    }

                    Text("You don't have to add every department now. Adding one later is safe. Setting up again only adds what's new.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.top, 4)
                } else {
                    Text("Type your organization's name to see the plan.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What this will create, preview")
    }
}

// MARK: - Surface 6: Integrations (education only, collects nothing)

extension AdminRootView {
    var integrationsView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Integrations",
            intro: "An integration here is a small command-line tool a developer builds, so a copilot can reach a system like Salesforce or your calendar. It isn't something you switch on."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("It cascades.").font(.body.weight(.semibold))
                            Text("Built and published for the whole organization, it's inherited by every department. Published for one department, it belongs only there. Published nowhere, it exists for no one.")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The key lives elsewhere.").font(.body.weight(.semibold))
                            Text("An integration names the key it needs. The key never comes near this app. It lives in the shared store, handed out only to the right team.")
                        }
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How integrations will arrive")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text("1. An engineer on a department builds skills, agents, and integrations inside that department's spaces. Give an engineer write access to a department's team and they can build there.")
                    Text("2. Each integration is added to a registry, a plain document that lives in the same space and lists what has been built.")
                    Text("3. Merging that document to the main copy publishes the integration.")
                    Text("4. From then on, the people entitled to that space see it, and the app your team uses can let them know when a new one arrives.")
                }
                .font(.body)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

                registryPreview

                Text("There's nothing to set up here today. No integrations exist yet, and that's expected. They arrive when your departments' engineers build and publish them.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } leadingActions: {
            backButton { model.goBack(from: .integrations) }
        } primaryAction: {
            primaryButton("Continue") { model.advance(from: .integrations) }
        }
    }

    /// A fully inert, clearly-labeled future-state mock (interaction-design
    /// Surface 6): no tab stops, no hover, no cursor change, example data only.
    private var registryPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW · not live")
                .font(.caption2.weight(.bold))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            VStack(alignment: .leading, spacing: 6) {
                Text("acme-co/cli-copilot-sales · registry (example)")
                    .font(.system(.callout, design: .monospaced))
                Text("salesforce-lookup   needs SALESFORCE_API_KEY")
                    .font(.system(.callout, design: .monospaced))
                Text("calendar-read   needs GOOGLE_CAL_TOKEN")
                    .font(.system(.callout, design: .monospaced))
            }
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text("This is what a published registry will look like. It is an example, not your data, and nothing here is clickable.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview, example only, not interactive")
    }
}

// MARK: - Surface 7: Secret store

extension AdminRootView {
    var secretStoreView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Your shared secret store",
            intro: "A shared secret store is one service that holds your organization's keys and hands them out by team. Shared integrations need it: an integration names the key it needs, and at runtime the store checks that the person is on the right GitHub team and only then hands over the key. That is why a key never lives in a repo or in this app."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard(title: "Connect a store") {
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
                            placeholder: "https://vault.acme-co.com",
                            helpText: "This is a web address, not a secret."
                        )
                        .frame(maxWidth: 360)
                        .onChange(of: model.storeAddress) { model.storeAddressTouchedInvalid = true }

                        if model.storeAddressTouchedInvalid, !model.storeAddressLooksValid {
                            Text("That doesn't look like a valid address.")
                                .font(.caption)
                                .foregroundColor(Color(nsColor: .systemRed))
                        }

                        if model.storeKind == .infisical {
                            SecretGuardedField(
                                label: "Workspace ID",
                                value: $model.storeWorkspaceID,
                                placeholder: "Infisical project ID",
                                helpText: "This identifies the workspace; it is not a secret."
                            )
                            .frame(maxWidth: 360)
                            SecretGuardedField(
                                label: "Environment",
                                value: $model.storeEnvironment,
                                placeholder: "prod"
                            )
                            .frame(maxWidth: 360)
                            SecretGuardedField(
                                label: "Shared secret path",
                                value: $model.storeSecretPath,
                                placeholder: "/shared",
                                helpText: "Each device receives read-only access to this exact path."
                            )
                            .frame(maxWidth: 360)
                            if !model.storeConnectionDetailsAreValid {
                                Text("Add the workspace ID, environment, and a path beginning with /.")
                                    .font(.caption)
                                    .foregroundColor(Color(nsColor: .systemRed))
                            }
                        }

                        if !model.departments.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Which teams can use it")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                ForEach(model.departments) { dept in
                                    if !dept.slug.isEmpty {
                                        HStack {
                                            Text(dept.name)
                                                .frame(width: 120, alignment: .leading)
                                            Text("→")
                                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            SecretGuardedField(
                                                label: "",
                                                value: model.scopeBinding(for: dept),
                                                placeholder: "dept/\(dept.slug)"
                                            )
                                            .frame(maxWidth: 220)
                                        }
                                    }
                                }
                            }
                        }

                        if model.storeStatus == .connected {
                            Text("Connected. This will be included when you hand off.")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .systemGreen))
                        }
                    }
                }

                AdminCard(title: "No store yet?") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shared integrations can't work until you connect a store. You have no integrations yet, so you can finish setting up now and connect a store before your first one is built.")
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pause and go get one. Common shared stores are 1Password, Infisical, and Vault (also called OpenBao). Set one up, then come back with its web address.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://github.com/Everyone-Needs-A-Copilot")!)
                            } label: {
                                Text("How to set one up ›")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .controlAccentColor))
                        }

                        HStack {
                            Text("Skip this for now. You'll be reminded to connect a store before your first shared integration can work.")
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                model.finishSecretStore(connect: false)
                            } label: {
                                Text("Skip for now")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                }
            }
        } leadingActions: {
            backButton { model.goBack(from: .secretStore) }
        } primaryAction: {
            primaryButton("Continue", enabled: model.storeAddressLooksValid && !model.storeAddress.isEmpty && model.storeConnectionDetailsAreValid) {
                model.finishSecretStore(connect: true)
            }
        }
    }
}

// MARK: - Surface 8: Review and hand off

extension AdminRootView {
    var reviewView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Review organization setup",
            intro: "Here's the complete private repository plan. Setup checks every target first, reuses existing private repositories, and creates only repositories GitHub confirms are missing."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard {
                    Text("This adds and updates. It never deletes or overwrites anything already there.")
                        .font(.body.weight(.medium))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                AdminCard(title: "What setup will create") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Org spaces: knowledge, CLI, Claude, and Codex repositories ending in -internal. Private.")
                        ForEach(model.departments.filter { !$0.slug.isEmpty }) { dept in
                            Text("\(dept.name): four spaces and a team for \(dept.name) that can reach them.")
                        }
                        Text("Your organization's setup file (ecosystem.yml).")
                        Text("Your organization's public GitHub OAuth App client ID. The client secret is never collected.")
                        Text("Your whole organization set to read by default.")
                        Text("Harnesses: Claude and Codex. Default: \(model.harness.displayName).")
                        Text(model.storeStatus == .connected ? "Store: connected." : "Store: not connected yet.")
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                }

                briefCard
                repositoryInventoryCard
            }
        } leadingActions: {
            backButton { model.goBack(from: .review) }
        } primaryAction: {
            primaryButton(
                model.repositoryApplyState == .working ? "Setting up…" : "Set up organization",
                enabled: model.githubOAuthClientIDIsValid && model.repositoryPlanState == .success && model.repositoryPlan?.result != .blocked && model.repositoryApplyState != .working
            ) {
                Task {
                    await model.applyRepositoryPlan()
                    if model.repositoryApplyState == .success {
                        model.advance(from: .review)
                    }
                }
            }
        }
        .task {
            await performReviewWriteIfNeeded()
        }
    }

    private var briefCard: some View {
        AdminCard(title: "The file setup wrote for you") {
            VStack(alignment: .leading, spacing: 8) {
                switch model.briefWriteState {
                case .idle, .working:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Writing your setup file...")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                case .failure:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again.")
                            .foregroundColor(Color(nsColor: .systemRed))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try again") {
                            Task { await performReviewWrite() }
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
                        Text("At a glance: \(model.orgSlug) · \(model.harness.displayName) · \(model.departments.filter { !$0.slug.isEmpty }.count) departments · \(model.storeAtAGlance).")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("It carries no secrets and no integrations.")
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }

    private var repositoryInventoryCard: some View {
        AdminCard(title: "GitHub repository inventory") {
            VStack(alignment: .leading, spacing: 8) {
                switch model.repositoryPlanState {
                case .idle, .working:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking every organization and department repository…")
                    }
                case .failure:
                    Text(model.repositorySetupMessage ?? "I couldn't read the repository inventory, so I won't create anything.")
                        .foregroundColor(Color(nsColor: .systemRed))
                    Button("Try again") { Task { await model.loadRepositoryPlan() } }
                        .buttonStyle(.bordered)
                case .success:
                    if let plan = model.repositoryPlan {
                        ForEach(plan.repositories, id: \.name) { repository in
                            HStack(alignment: .top, spacing: 8) {
                                Text(repository.state == .existingPrivate ? "✓" : (repository.state == .missing ? "+" : "!"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(repository.owner)/\(repository.name)")
                                        .font(.system(.callout, design: .monospaced))
                                    Text(repository.detail)
                                        .font(.caption)
                                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                }
                            }
                        }
                        Text("Existing private repositories are reused. Only confirmed-missing repositories are created, and every new repository is private.")
                            .font(.callout.weight(.medium))
                    }
                    if let message = model.repositorySetupMessage {
                        Text(message)
                            .foregroundColor(model.repositoryPlan?.result == .blocked ? Color(nsColor: .systemRed) : Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }

    private func openTerminalAndAdvance() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        model.advance(from: .review)
    }

    /// Rewrites the brief only when something that feeds it actually
    /// changed since the last write (`AdminModel.briefFingerprint`), so
    /// re-visiting Review unchanged never spuriously rewrites, but Back +
    /// edit + return always does (QA fix: this used to be a one-shot
    /// `reviewCommandGenerated` flag that left a stale brief/command in
    /// place after an edit).
    private func performReviewWriteIfNeeded() async {
        guard model.lastWrittenBriefFingerprint != model.briefFingerprint else { return }
        await performReviewWrite()
    }

    private func performReviewWrite() async {
        let fingerprint = model.briefFingerprint
        await model.writeBrief()
        if model.briefWriteState == .success {
            model.lastWrittenBriefFingerprint = fingerprint
            await model.loadRepositoryPlan()
        }
    }
}
