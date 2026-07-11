//
// Copilot Control Tower — Admin mode (the 16-surface baton-pass rebuild).
// Two faces, one binary: `control-tower-tray.swift` is the user face (Bob);
// this file (+ `native/admin-support.swift`) is the Admin face (Earl).
// Reached via the tray's right-click menu ("Open Administration...") or
// `CT_OPEN_ADMIN=1` at launch — both call `AdminWindowController.shared.show()`,
// the one seam `control-tower-tray.swift` depends on; nothing else there
// changed for this rebuild.
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
//     the brief file format (§1), the handoff command (§2), the verify verb
//     JSON (§3). `scripts/admin_bootstrap.sh` (owned by a parallel agent; NOT
//     touched by this file) implements the engine side of that contract.
//   - docs/03-design/control-tower-visual-system.md — the "Quiet Instrument"
//     language (shape-first status, `surface.field` for code/handoff blocks,
//     no raw error strings, no time estimates, no em-dashes).
//
// REAL vs HONESTLY-DEGRADED (no mocks pretending to be real):
//   - Connect GitHub (this file, below) shells real, read-only local checks:
//     `gh --version`, `gh auth status` (parsed for sign-in + scopes), and
//     `command -v claude`. The ONE thing NOT locally checkable from the
//     sanctioned detection set is GitHub org ownership (no `gh api` call is
//     sanctioned here) — that row is honestly rendered as a permanent "can't
//     check this from here" (`// CONTRACT SEAM` below), never a fabricated
//     pass.
//   - The Setup check (`native/admin-support.swift`) shells the real
//     `scripts/admin_bootstrap.sh --verify --brief <path> --json` and renders
//     its rows verbatim; if the engine or `gh` is missing, it renders the
//     honest degraded state (`unknown`, never a fabricated green).
//   - The brief writer and skill materializer (`native/admin-support.swift`)
//     perform real file I/O against the paths the contract names.
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
// (handoff header + sidebar + root shell), and surfaces 1-8 (Orientation
// through Review and hand off). `native/admin-support.swift` holds surfaces
// 9-16 (Handed off through the five Governance surfaces), the verify/brief/
// skill plumbing, and `AdminWindowController`. Both compile into the same
// module (`swiftc native/*.swift`), so types split freely across the two.

import AppKit
import SwiftUI

// MARK: - Process runner (real, read-only shell-outs only)

/// Runs a command inside the user's own login shell so PATH resolution
/// matches what Earl would see in his own Terminal (Homebrew, asdf, etc.),
/// the same reasoning `scripts/publisher_setup.swift`'s `runStreamingCommand`
/// documents for its own `/bin/bash -lc` calls. Always off the main thread;
/// never called from a SwiftUI `init()` (see this file's header).
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

    /// Materializes the bundled skill (admin-standup-contract.md §2.1), but
    /// NOT as a byte-for-byte copy: the operator runs the materialized copy
    /// from an arbitrary terminal `cwd` (their home directory, not the repo),
    /// so every repo-relative `bash scripts/admin_bootstrap.sh` run command
    /// in the source is rewritten to `bash "<absolute enginePath>"` (quoted,
    /// so a path containing spaces still works) before it's written to
    /// `destination`. The repo copy at `source` is never touched, so a
    /// clone-and-run of the skill straight from the repository keeps the
    /// repo-relative form and runs from the repository root.
    ///
    /// Idempotent by content, not mtime: writes only when the transformed
    /// text actually differs from what's already at `destination` (covers
    /// both "not materialized yet" and "the bundled skill or the engine path
    /// changed since the last materialize").
    static func materializeSkill(source: String, destination: String, enginePath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let sourceData = fm.contents(atPath: source),
                      let sourceText = String(data: sourceData, encoding: .utf8)
                else {
                    continuation.resume(returning: false)
                    return
                }

                let transformed = sourceText.replacingOccurrences(
                    of: "bash scripts/admin_bootstrap.sh",
                    with: "bash \"\(enginePath)\""
                )

                if let existingData = fm.contents(atPath: destination),
                   let existingText = String(data: existingData, encoding: .utf8),
                   existingText == transformed {
                    continuation.resume(returning: true)
                    return
                }

                do {
                    let destURL = URL(fileURLWithPath: destination)
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try transformed.write(to: destURL, atomically: true, encoding: .utf8)
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

    /// CONTRACT SEAM: the interim engine's path, injectable in this one place
    /// so the WS-A freeze swap to `copilot admin bootstrap --verify --json`
    /// (contract §8) only touches this constant. Resolved relative to the
    /// working directory, the same convention `AviatorGlyph`/`ControlTowerGlyph`
    /// use in `models.swift` (the launcher `cd`s to the repo root first).
    static var enginePath: String {
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: "scripts/admin_bootstrap.sh", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL.path
    }

    /// §2.1: the bundled OSS skill this prototype ships repo-relative, and the
    /// fixed user-scope location Review-and-hand-off materializes it to.
    static var bundledSkillSourcePath: String {
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: ".claude/skills/admin-bootstrap/SKILL.md", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL.path
    }

    static var materializedSkillDestPath: String {
        NSHomeDirectory() + "/.claude/skills/admin-bootstrap/SKILL.md"
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
        case .review: return "Review and hand off"
        case .handedOff: return "Handed off"
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
        case .handedOff: return "terminal"
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

/// Connect GitHub's five readiness rows (interaction-design Surface 4; copy
/// deck §3.6). `owner` (row 3) is a `// CONTRACT SEAM`: the sanctioned local
/// detection set (gh presence/version, `gh auth status` sign-in + scopes,
/// Claude Code presence) has no real check for GitHub org ownership, so this
/// row can never honestly reach `.pass` here — it renders a permanent,
/// truthful "can't check this from here" rather than a fabricated green.
enum ReadinessStatus: Equatable {
    case notChecked
    case checking
    case pass
    case fail
    case cannotCheckLocally
}

struct ReadinessRow: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case ghInstalled, signedIn, owner, scopes, claudeInstalled
        var id: String { rawValue }
    }

    var id: Kind { kind }
    let kind: Kind
    var status: ReadinessStatus = .notChecked
    var detail: String = ""
    var copyCommand: String? = nil

    func baseTitle(org: String) -> String {
        switch kind {
        case .ghInstalled: return "GitHub's command-line tool is installed"
        case .signedIn: return "You're signed in"
        case .owner: return "Your account is an owner of \(org.isEmpty ? "your organization" : org)"
        case .scopes: return "Your sign-in has the access setup needs"
        case .claudeInstalled: return "Claude Code is installed"
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
    @Published var readinessRows: [ReadinessRow] = ReadinessRow.Kind.allCases.map { ReadinessRow(kind: $0) }
    @Published var githubChecking = false
    @Published var githubCheckDegraded = false
    @Published var copiedCommandID: String? = nil

    /// The org identity is an EXISTING GitHub organization name, not a value
    /// this app derives or slugifies: it is used verbatim (trimmed of
    /// surrounding whitespace only), case preserved, so an org actually
    /// named `Acme-Copilot` is never silently lowercased to `acme-copilot`
    /// in the plan card, the brief, or the Setup check. Departments stay
    /// app-derived slugs (`AdminSlug.derive`), unchanged, since their repo
    /// names are generated, not an existing identifier.
    var orgSlug: String { orgNameInput.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Surface 5: Describe your organization
    @Published var harness: Harness = .codex
    @Published var departments: [DepartmentEntry] = []
    @Published var orgSlugTouched = false

    // Surface 7: Secret store
    @Published var storeKind: StoreKind = .infisical
    @Published var storeAddress = ""
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
    @Published var skillMaterializeState: WriteState = .idle
    @Published var lastWrittenBriefFingerprint: String? = nil

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

    // Governance: Connect the shared store
    @Published var governanceStoreCommandReady = false

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

    // MARK: Connect GitHub (real, read-only, sanctioned detection only)

    func checkGitHubReadiness() {
        Task { await runGitHubReadinessCheck() }
    }

    private func runGitHubReadinessCheck() async {
        githubChecking = true
        githubCheckDegraded = false
        for i in readinessRows.indices { readinessRows[i].status = .checking }

        let ghVersion = await ShellRunner.run("gh --version")
        let ghPresent = ghVersion.exitCode == 0 && !ghVersion.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if ghPresent {
            var row = readinessRows[.ghInstalled]
            row.status = .pass
            row.detail = ""
            row.copyCommand = nil
            readinessRows[.ghInstalled] = row
        } else {
            var row = readinessRows[.ghInstalled]
            row.status = .fail
            row.detail = "GitHub's command-line tool isn't on this Mac yet. Setup runs through it."
            row.copyCommand = "brew install gh"
            readinessRows[.ghInstalled] = row
        }

        if ghPresent {
            let auth = await ShellRunner.run("gh auth status 2>&1")
            let combined = auth.stdout + auth.stderr
            let signedIn = combined.lowercased().contains("logged in to")

            var signedInRow = readinessRows[.signedIn]
            if signedIn {
                signedInRow.status = .pass
                signedInRow.detail = ""
                signedInRow.copyCommand = nil
            } else {
                signedInRow.status = .fail
                signedInRow.detail = "You're not signed in to GitHub's command-line tool yet."
                signedInRow.copyCommand = "gh auth login"
            }
            readinessRows[.signedIn] = signedInRow

            var scopesRow = readinessRows[.scopes]
            if signedIn {
                let hasAdminOrg = combined.contains("admin:org")
                let hasRepo = combined.contains("'repo'") || combined.contains("\"repo\"")
                if hasAdminOrg && hasRepo {
                    scopesRow.status = .pass
                    scopesRow.detail = ""
                    scopesRow.copyCommand = nil
                } else {
                    scopesRow.status = .fail
                    scopesRow.detail = "Your GitHub sign-in is missing the access setup needs."
                    scopesRow.copyCommand = "gh auth refresh -s admin:org -s repo"
                }
            } else {
                scopesRow.status = .cannotCheckLocally
                scopesRow.detail = "Can't check this until you're signed in."
                scopesRow.copyCommand = nil
            }
            readinessRows[.scopes] = scopesRow
        } else {
            var signedInRow = readinessRows[.signedIn]
            signedInRow.status = .cannotCheckLocally
            signedInRow.detail = "Can't check this until GitHub's command-line tool is installed."
            readinessRows[.signedIn] = signedInRow

            var scopesRow = readinessRows[.scopes]
            scopesRow.status = .cannotCheckLocally
            scopesRow.detail = "Can't check this until GitHub's command-line tool is installed."
            readinessRows[.scopes] = scopesRow
        }

        // CONTRACT SEAM: org ownership has no sanctioned local check (it would
        // need a live `gh api orgs/<org>/memberships/<user>` read, which is
        // outside the sanctioned detection set for this surface). Render this
        // honestly: never fabricated green, never a hard block either.
        var ownerRow = readinessRows[.owner]
        ownerRow.status = .cannotCheckLocally
        ownerRow.detail = "This app can't check organization ownership from this Mac. If setup later says you're not one, ask an owner to run this, or to make you one."
        readinessRows[.owner] = ownerRow

        let claude = await ShellRunner.run("command -v claude")
        var claudeRow = readinessRows[.claudeInstalled]
        if claude.exitCode == 0 && !claude.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            claudeRow.status = .pass
            claudeRow.detail = ""
        } else {
            claudeRow.status = .fail
            claudeRow.detail = "Claude Code isn't on this Mac yet. Setup runs there, so you'll want it before you hand off."
        }
        readinessRows[.claudeInstalled] = claudeRow

        githubChecking = false
    }

    func copyToClipboard(_ text: String, id: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        copiedCommandID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.copiedCommandID == id {
                self?.copiedCommandID = nil
            }
        }
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
        let token = harness.repoToken
        lines.append("Three shared spaces for your whole organization:")
        lines.append("\(org)/\(token)-copilot")
        lines.append("\(org)/knowledge-copilot")
        lines.append("\(org)/cli-copilot   Private.")
        for dept in departments where !dept.slug.isEmpty {
            let display = dept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("")
            lines.append("Three spaces for the \(display) department:")
            lines.append("\(org)/\(token)-copilot-\(dept.slug)")
            lines.append("\(org)/knowledge-copilot-\(dept.slug)")
            lines.append("\(org)/cli-copilot-\(dept.slug)   Private.")
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
        if connect, !storeAddress.isEmpty, SecretShapeCheck.looksLikeURL(storeAddress) {
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
        var parts: [String] = [orgSlug, harness.rawValue]
        parts.append(contentsOf: validDepartments.map { $0.slug })
        switch storeStatus {
        case .connected:
            parts.append("connected")
            parts.append(storeKindSlug)
            parts.append(storeAddress)
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
                        Text("2. Claude Code sets it up in your terminal.")
                        Text("3. Come back and run the Setup check.")
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                }

                Text("This app never changes anything on GitHub itself. It gets you ready, hands the work to Claude Code, and checks the result.")
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
            intro: "A few things need to be true before setup can run. None of them happen here. This is just so nothing stops you halfway."
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
                        Text("You have GitHub's command-line tool and Claude Code on this Mac. The next step checks and helps.")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(Color(nsColor: .secondaryLabelColor))
                        Text("Setup needs permission to work in your GitHub organization. It creates your shared repositories and sets up your teams and their access, so the GitHub command-line tool needs two permissions, called scopes: repo and admin:org. The next step checks for these and gives you the exact command to grant them if they are missing.")
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
            intro: "A quick check that this Mac can run the terminal session. This changes nothing. Claude Code checks all of this again when setup runs, and helps you fix anything that's off."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    SecretGuardedField(label: "", value: $model.orgNameInput, placeholder: "acme-co")
                        .frame(maxWidth: 320)
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

                Text("This step just gives you a head start. It never blocks the hand-off.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        } leadingActions: {
            backButton { model.goBack(from: .connectGitHub) }
            if model.githubChecking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking your GitHub access...")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
        } primaryAction: {
            primaryButton("Check again") {
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
                    if let command = row.copyCommand {
                        CopyableCodeBlock(text: command)
                            .frame(maxWidth: 360)
                    }
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
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

                    Text("This is your organization's default. Anyone can still use the other harness for themselves, on the open-source foundation plus their own personal setup. And you can add the second harness for the whole organization later, as a safe re-run that only adds what's new.")
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
            primaryButton("Continue") {
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
            title: "Review and hand off",
            intro: "Here's everything setup will create. Copy the command below, open your terminal, and paste it. Claude Code walks you through the rest and checks everything with GitHub as it goes."
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
                        Text("Org spaces: \(model.orgSlug)/\(model.harness.repoToken)-copilot, \(model.orgSlug)/knowledge-copilot, \(model.orgSlug)/cli-copilot. Private.")
                        ForEach(model.departments.filter { !$0.slug.isEmpty }) { dept in
                            Text("\(dept.name): three spaces and a team for \(dept.name) that can reach them.")
                        }
                        Text("Your organization's setup file (ecosystem.yml).")
                        Text("Your whole organization set to read by default.")
                        Text("Harness: \(model.harness.displayName).")
                        Text(model.storeStatus == .connected ? "Store: connected." : "Store: not connected yet.")
                    }
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                }

                briefCard

                commandCard
            }
        } leadingActions: {
            backButton { model.goBack(from: .review) }
        } primaryAction: {
            primaryButton("Open Terminal") {
                openTerminalAndAdvance()
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

    private var commandCard: some View {
        AdminCard(title: "The setup command") {
            if model.briefWriteState == .success && model.skillMaterializeState == .success {
                VStack(alignment: .leading, spacing: 10) {
                    CopyableCodeBlock(text: model.handoffCommand, copyLabel: "Copy the setup command")
                    Text("This hands Claude Code a plain description of your organization. It carries no secrets. Claude Code checks it with you, then does the work.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("When Claude Code says it's done, come back here and run the Setup check.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        model.advance(from: .review)
                    } label: {
                        Text("When you've pasted it, come here to wait ›")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: .controlAccentColor))
                }
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            } else if model.skillMaterializeState == .failure {
                Text("I couldn't get the setup skill ready on this Mac, so I won't hand off a command that can't run. Try again.")
                    .foregroundColor(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Getting the setup skill ready...")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
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
        await model.writeBriefAndMaterializeSkill()
        if model.briefWriteState == .success {
            model.lastWrittenBriefFingerprint = fingerprint
        }
    }
}
