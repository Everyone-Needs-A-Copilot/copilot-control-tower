#!/usr/bin/env swift
import SwiftUI
import Foundation

// MARK: - Data

struct SigningIdentity: Identifiable, Hashable {
    let id: String
    let name: String
    let teamId: String
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum TrustState: Equatable {
    case verifying
    case trusted
    case untrustedFixable
    case missingKey
}

enum FailureOrigin: Equatable {
    case setup
    case publish
}

/// The seven persistent stages shown in the roadmap sidebar (design spec §2.2).
enum RoadmapStage: Int, CaseIterable, Identifiable {
    case welcome
    case prerequisites
    case identity
    case trustVerify
    case notaryConfig
    case build
    case handoff

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .prerequisites: return "Prerequisites"
        case .identity: return "Signing Identity"
        case .trustVerify: return "Trust Verify"
        case .notaryConfig: return "Notary & Config"
        case .build: return "Build"
        case .handoff: return "Handoff"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "checkmark.seal"
        case .prerequisites: return "checklist"
        case .identity: return "person.badge.key"
        case .trustVerify: return "checkmark.shield"
        case .notaryConfig: return "paperplane"
        case .build: return "hammer"
        case .handoff: return "shippingbox"
        }
    }
}

enum SetupPhase {
    case welcome
    case prerequisites
    case guide(PublisherGuide)
    case identity
    case trustVerify
    case form
    case success(SetupSuccess)
    case publishing
    case published(PublishArtifact)
    case failure(SetupFailure)
}

/// Derives the roadmap position from the current phase. Failure is rendered inline and does
/// not introduce its own stage (design spec §2.2). It reports the stage it interrupted.
func currentStage(for phase: SetupPhase, failureStage: RoadmapStage) -> RoadmapStage {
    switch phase {
    case .welcome:
        return .welcome
    case .prerequisites, .guide:
        return .prerequisites
    case .identity:
        return .identity
    case .trustVerify:
        return .trustVerify
    case .form:
        return .notaryConfig
    case .success, .publishing:
        return .build
    case .published:
        return .handoff
    case .failure:
        return failureStage
    }
}

enum PublisherGuide: String, CaseIterable, Identifiable {
    case membership
    case certificate
    case intermediate
    case appPassword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .membership:
            return "Apple Developer Membership"
        case .certificate:
            return "Developer ID Certificate"
        case .intermediate:
            return "Developer ID - G2 Trust"
        case .appPassword:
            return "App-Specific Password"
        }
    }

    var checklistText: String {
        switch self {
        case .membership:
            return "Apple Developer membership is active for this Team ID."
        case .certificate:
            return "Developer ID Application certificate is installed, trusted, and has its private key."
        case .intermediate:
            return "Developer ID - G2 intermediate is installed if Keychain ever showed the cert as untrusted."
        case .appPassword:
            return "An Apple-generated app-specific password is ready to paste."
        }
    }

    var symbol: String {
        switch self {
        case .membership:
            return "person.crop.circle.badge.checkmark"
        case .certificate:
            return "lock.doc"
        case .intermediate:
            return "link.badge.plus"
        case .appPassword:
            return "key.horizontal"
        }
    }

    var why: String {
        switch self {
        case .membership:
            return "Control Tower releases need an Apple Developer Team ID. That Team ID is what Apple uses to connect the signing certificate, notarization account, and the app artifact that macOS will evaluate."
        case .certificate:
            return "The Developer ID Application certificate proves who published the macOS app. The private key underneath the certificate is the part this Mac uses to sign the app locally."
        case .intermediate:
            return "macOS must trust the certificate chain before signed releases are useful. If Keychain marks the Developer ID certificate as untrusted, installing Apple's Developer ID - G2 intermediate usually completes that chain."
        case .appPassword:
            return "Notarization uploads the signed app to Apple for automated security checks. Apple requires an app-specific password for notarytool; your normal Apple ID password and password-manager-generated random passwords will be rejected."
        }
    }

    var steps: [String] {
        switch self {
        case .membership:
            return [
                "Sign in at developer.apple.com/account.",
                "Open Membership details.",
                "Confirm the account is enrolled in the Apple Developer Program.",
                "Copy the Team ID and make sure it matches the Team ID shown in Publisher Setup."
            ]
        case .certificate:
            return [
                "Open Keychain Access.",
                "Go to login > My Certificates.",
                "Find Developer ID Application: Your Name (TEAMID).",
                "Expand it and confirm a private key appears underneath.",
                "If the private key is missing, recreate the certificate from a CSR generated on this Mac."
            ]
        case .intermediate:
            return [
                "If the Developer ID certificate is trusted already, you can continue.",
                "If Keychain marks it as untrusted, download Apple's Developer ID - G2 certificate.",
                "Open the downloaded certificate to install it into Keychain.",
                "Return to Keychain Access and confirm the Developer ID Application certificate is trusted."
            ]
        case .appPassword:
            return [
                "Sign in at account.apple.com with the Apple Developer Apple ID for this Team ID.",
                "Open Sign-In and Security.",
                "Open App-Specific Passwords.",
                "Generate a password named Control Tower Notary.",
                "Keep the generated value available only long enough to paste it into Publisher Setup."
            ]
        }
    }

    var actionTitle: String? {
        switch self {
        case .membership:
            return "Open Developer Account"
        case .certificate:
            return nil
        case .intermediate:
            return "Open Apple Certificates"
        case .appPassword:
            return "Open Apple Account"
        }
    }

    var actionURL: URL? {
        switch self {
        case .membership:
            return URL(string: "https://developer.apple.com/account")
        case .certificate:
            return nil
        case .intermediate:
            return URL(string: "https://www.apple.com/certificateauthority/")
        case .appPassword:
            return URL(string: "https://account.apple.com")
        }
    }
}

struct SetupSuccess {
    let envFile: String
    let profileName: String
    let identity: String
    let notarySkipped: Bool
}

struct SetupFailure {
    let title: String
    let message: String
    let recovery: String
    let details: String
    let actionTitle: String?
    let actionURL: URL?
}

struct PublishArtifact {
    let appPath: String
    let dmgPath: String
    let log: String
    let notarizedSkipped: Bool
}

@MainActor
final class PublisherSetupModel: ObservableObject {
    @Published var identities: [SigningIdentity] = []
    @Published var selectedIdentityId: String = ""
    @Published var appleId: String = ""
    @Published var profileName: String = "ct-notary"
    @Published var envFile: String = ".env.release.local"
    @Published var password: String = ""
    @Published var skipNotary: Bool = false
    @Published var replaceExisting: Bool = false
    @Published var isRunning: Bool = false
    @Published var status: String = "Looking for Developer ID Application certificates..."
    @Published var phase: SetupPhase = .welcome
    @Published var copiedMessage: String = ""
    @Published var publishStep: String = ""
    @Published var publishLog: String = ""
    @Published var trustState: TrustState = .verifying
    @Published var failureOrigin: FailureOrigin = .setup
    @Published var failureStage: RoadmapStage = .prerequisites
    @Published var lastSetupSuccess: SetupSuccess?
    @Published var lastArtifact: PublishArtifact?

    var selectedIdentity: SigningIdentity? {
        identities.first { $0.id == selectedIdentityId }
    }

    var currentRoadmapStage: RoadmapStage {
        currentStage(for: phase, failureStage: failureStage)
    }

    init() {
        // Deliberately does not call refreshIdentities() here. `@StateObject` initialization
        // runs synchronously during SwiftUI's first layout/sizing pass: if refreshIdentities()
        // ran a blocking `Process` here, `waitUntilExit()` would pump a nested CFRunLoop that
        // re-enters the AttributeGraph mid-update and aborts (AG::precondition_failure). The
        // refresh is instead triggered from the view's `.task` after first render (see
        // PublisherSetupView.body), and refreshIdentities() itself runs its subprocess off the
        // main thread.
    }

    // MARK: Navigation

    func goWelcome() {
        copiedMessage = ""
        phase = .welcome
    }

    func showPrerequisites() {
        copiedMessage = ""
        phase = .prerequisites
    }

    func showGuide(_ guide: PublisherGuide) {
        copiedMessage = ""
        phase = .guide(guide)
    }

    func goIdentity() {
        copiedMessage = ""
        refreshIdentities()
        phase = .identity
    }

    func goTrustVerify() {
        copiedMessage = ""
        phase = .trustVerify
        verifyCertTrust()
    }

    func beginSetup() {
        copiedMessage = ""
        phase = .form
    }

    func editSetup() {
        copiedMessage = ""
        phase = .form
    }

    func reviewStage(_ stage: RoadmapStage) {
        copiedMessage = ""
        switch stage {
        case .welcome:
            phase = .welcome
        case .prerequisites:
            phase = .prerequisites
        case .identity:
            phase = .identity
        case .trustVerify:
            phase = .trustVerify
        case .notaryConfig:
            phase = .form
        case .build:
            if let success = lastSetupSuccess {
                phase = .success(success)
            } else {
                phase = .form
            }
        case .handoff:
            if let artifact = lastArtifact {
                phase = .published(artifact)
            }
        }
    }

    func retryAfterFailure() {
        copiedMessage = ""
        if failureOrigin == .publish, let success = lastSetupSuccess {
            phase = .success(success)
        } else {
            phase = .form
        }
    }

    // MARK: Identity + trust

    /// Runs `security find-identity` off the main thread so it never pumps a nested run loop
    /// (via `Process.waitUntilExit()`) while SwiftUI is mid-layout/AttributeGraph-update. That
    /// re-entrancy is what caused the launch-time SIGABRT this method used to trigger when
    /// called synchronously from `init()`.
    func refreshIdentities() {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<[SigningIdentity], Error>
            do {
                let output = try runCommand("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]).output
                outcome = .success(parseIdentities(output))
            } catch {
                outcome = .failure(error)
            }

            DispatchQueue.main.async {
                switch outcome {
                case .success(let parsed):
                    self.identities = parsed
                    if self.selectedIdentityId.isEmpty || !parsed.contains(where: { $0.id == self.selectedIdentityId }) {
                        self.selectedIdentityId = parsed.first?.id ?? ""
                    }
                    self.status = parsed.isEmpty
                        ? "No Developer ID Application certificate was found. Install the certificate and the Developer ID - G2 intermediate first."
                        : "Found \(parsed.count) Developer ID Application signing identity\(parsed.count == 1 ? "" : "ies")."
                case .failure(let error):
                    self.identities = []
                    self.selectedIdentityId = ""
                    self.status = "Could not inspect signing identities: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Verifies the selected identity has a private key and a trusted chain by rendering
    /// `security find-identity` results. It never fabricates a deeper trust evaluation than the
    /// tool provides (design spec §3.5, invariant #1: parse, never compute).
    func verifyCertTrust() {
        guard let identity = selectedIdentity else {
            trustState = .missingKey
            return
        }
        trustState = .verifying
        let name = identity.name

        DispatchQueue.global(qos: .userInitiated).async {
            let validOutput = (try? runCommand("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]).output) ?? ""
            let allOutput = (try? runCommand("/usr/bin/security", ["find-identity", "-p", "codesigning"]).output) ?? ""
            let validNames = Set(parseIdentities(validOutput).map { $0.name })
            let allNames = Set(parseIdentities(allOutput).map { $0.name })

            let result: TrustState
            if validNames.contains(name) {
                result = .trusted
            } else if allNames.contains(name) {
                result = .untrustedFixable
            } else {
                result = .missingKey
            }

            DispatchQueue.main.async {
                self.trustState = result
            }
        }
    }

    // MARK: Setup

    func setup() {
        guard let identity = selectedIdentity else {
            status = "Choose a Developer ID Application identity first."
            return
        }
        let trimmedProfile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnvFile = envFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfile.isEmpty else {
            status = "Enter a notary profile name."
            return
        }
        guard !trimmedEnvFile.isEmpty else {
            status = "Enter an env file path."
            return
        }
        if !skipNotary {
            guard !appleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = "Enter the Apple Developer Apple ID email for this Team ID."
                return
            }
            guard !password.isEmpty else {
                status = "Enter an Apple app-specific password, not your normal Apple ID password, or choose Skip notary."
                return
            }
        }

        isRunning = true
        status = "Setting up publisher machine..."

        let apple = appleId
        let appPassword = password
        let shouldSkipNotary = skipNotary
        let shouldReplace = replaceExisting
        let profile = trimmedProfile
        let env = trimmedEnvFile

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if !shouldSkipNotary {
                    try Self.storeNotaryProfile(
                        profileName: profile,
                        appleId: apple,
                        teamId: identity.teamId,
                        password: appPassword
                    )
                }

                try Self.writeEnvFile(
                    path: env,
                    identity: identity.name,
                    profileName: profile,
                    replaceExisting: shouldReplace
                )

                DispatchQueue.main.async {
                    self.password = ""
                    self.isRunning = false
                    self.status = "Publisher setup is ready."
                    let success = SetupSuccess(
                        envFile: env,
                        profileName: profile,
                        identity: identity.name,
                        notarySkipped: shouldSkipNotary
                    )
                    self.lastSetupSuccess = success
                    self.phase = .success(success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.password = ""
                    self.isRunning = false
                    self.status = "Setup failed."
                    self.failureOrigin = .setup
                    self.failureStage = .notaryConfig
                    self.phase = .failure(Self.failure(from: error))
                }
            }
        }
    }

    func publish(_ setup: SetupSuccess) {
        let appPath = "src-tauri/target/release/bundle/macos/Copilot Control Tower.app"
        let dmgBundleDir = "src-tauri/target/release/bundle/dmg"
        let productNamePrefix = "Copilot Control Tower"
        let notarizedSkipped = setup.notarySkipped

        isRunning = true
        copiedMessage = ""
        publishStep = "Preparing release commands..."
        publishLog = """
        Publisher Setup will build, sign, notarize, and staple the app.

        """
        phase = .publishing

        DispatchQueue.global(qos: .userInitiated).async {
            var log = ""

            do {
                var result = try Self.runReleaseStep(
                    title: "Build app",
                    command: #"PATH="/usr/bin:$PATH" CC=/usr/bin/cc npm run tauri build"#,
                    envFile: setup.envFile,
                    log: log
                ) { step, output in
                    DispatchQueue.main.async {
                        self.publishStep = step
                        self.publishLog = output
                    }
                }
                log = result.log
                try Self.requireReleaseStepSuccess("Build app", status: result.status)

                // Tauri v2 emits a versioned, arch-suffixed dmg filename (e.g.
                // "Copilot Control Tower_0.1.0_aarch64.dmg"), not a fixed name. Resolve the
                // artifact the build actually produced instead of assuming a literal path.
                let resolvedDmgPath: String
                do {
                    resolvedDmgPath = try Self.resolveDMGPath(bundleDir: dmgBundleDir, productPrefix: productNamePrefix)
                } catch {
                    log += "\n\(error.localizedDescription)\n"
                    let snapshot = log
                    DispatchQueue.main.async {
                        self.publishLog = snapshot
                    }
                    throw error
                }

                result = try Self.runReleaseStep(
                    title: "Sign app",
                    command: "./scripts/sign.sh \(shellQuote(appPath))",
                    envFile: setup.envFile,
                    log: log
                ) { step, output in
                    DispatchQueue.main.async {
                        self.publishStep = step
                        self.publishLog = output
                    }
                }
                log = result.log
                try Self.requireReleaseStepSuccess("Sign app", status: result.status)

                result = try Self.runReleaseStep(
                    title: "Notarize and staple",
                    command: "./scripts/notarize.sh \(shellQuote(appPath)) \(shellQuote(resolvedDmgPath))",
                    envFile: setup.envFile,
                    log: log
                ) { step, output in
                    DispatchQueue.main.async {
                        self.publishStep = step
                        self.publishLog = output
                    }
                }
                log = result.log
                try Self.requireReleaseStepSuccess("Notarize and staple", status: result.status)

                DispatchQueue.main.async {
                    self.isRunning = false
                    self.publishStep = "Release artifact is ready."
                    self.publishLog = log
                    let artifact = PublishArtifact(
                        appPath: appPath,
                        dmgPath: resolvedDmgPath,
                        log: log,
                        notarizedSkipped: notarizedSkipped
                    )
                    self.lastArtifact = artifact
                    self.phase = .published(artifact)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.publishStep = "Publishing stopped."
                    self.publishLog = log.isEmpty ? error.localizedDescription : log
                    self.failureOrigin = .publish
                    self.failureStage = .build
                    self.phase = .failure(Self.publishFailure(from: error, log: self.publishLog))
                }
            }
        }
    }

    func copy(_ value: String, label: String = "Copied") {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        copiedMessage = label
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ path: String) {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Builds the copyable Publisher → Admin handoff block (design spec §3.9). Update-signing
    /// status is always explicit, never silently implied as ready (invariant #4).
    func handoffText(for artifact: PublishArtifact) -> String {
        let identityName = selectedIdentity?.name ?? "Unknown signing identity"
        let teamId = selectedIdentity?.teamId ?? "Unknown"
        let version = Self.readAppVersion()
        let notarized = artifact.notarizedSkipped ? "No (skipped)" : "Yes"
        let updateSigning = "Not ready (updater signing not configured)"
        let producedFormatter = ISO8601DateFormatter()
        producedFormatter.formatOptions = [.withInternetDateTime]
        let produced = producedFormatter.string(from: Date())
        let hostName = ProcessInfo.processInfo.hostName

        return """
        PUBLISHER \u{2192} ADMIN HANDOFF
        App:              \(artifact.appPath)
        Disk image:       \(artifact.dmgPath)
        Team ID:          \(teamId)
        Signing identity: \(identityName)
        Version:          \(version)
        Notarized:        \(notarized)
        Update signing:   \(updateSigning)
        Produced:         \(produced) on \(hostName)
        """
    }

    nonisolated private static func readAppVersion() -> String {
        let path = "src-tauri/tauri.conf.json"
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String
        else {
            return "unknown"
        }
        return version
    }

    /// Loads the Control Tower brand icon from the repo the same way `readAppVersion()`
    /// resolves `tauri.conf.json`: repo-relative, resolved against the current working
    /// directory (the launcher `cd`s to the repo root before exec).
    nonisolated fileprivate static func loadBrandIcon() -> NSImage? {
        let path = "docs/reference/control-tower.svg"
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        guard let image = NSImage(contentsOfFile: url.path) else { return nil }
        if image.size == .zero {
            image.size = NSSize(width: 160, height: 160)
        }
        image.isTemplate = false
        return image
    }

    /// Globs the dmg bundle directory for the produced artifact instead of assuming a fixed
    /// filename. Tauri v2 emits a versioned, arch-suffixed dmg name.
    nonisolated private static func resolveDMGPath(bundleDir: String, productPrefix: String) throws -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let dirURL = URL(fileURLWithPath: bundleDir, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "PublisherSetup",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No dmg bundle output directory found at \(bundleDir). Confirm `npm run tauri build` produced a dmg bundle target."]
            )
        }

        let dmgFiles = entries.filter { $0.pathExtension.lowercased() == "dmg" }
        guard !dmgFiles.isEmpty else {
            throw NSError(
                domain: "PublisherSetup",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No .dmg file was found in \(bundleDir) after the build step."]
            )
        }

        let matching = dmgFiles.filter { $0.lastPathComponent.hasPrefix(productPrefix) }
        let candidates = matching.isEmpty ? dmgFiles : matching

        if candidates.count == 1 {
            return candidates[0].path
        }

        // Multiple candidates (e.g. a stale dmg from a previous build): prefer the most
        // recently modified one, since that is the artifact this run just produced.
        let sorted = candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }
        return sorted[0].path
    }

    nonisolated private static func storeNotaryProfile(profileName: String, appleId: String, teamId: String, password: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "notarytool",
            "store-credentials",
            profileName,
            "--apple-id",
            appleId,
            "--team-id",
            teamId,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        try process.run()
        if let bytes = "\(password)\n".data(using: .utf8) {
            stdin.fileHandleForWriting.write(bytes)
        }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = readPipe(stdout) + readPipe(stderr)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PublisherSetup",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: friendlyNotaryError(output)]
            )
        }
    }

    nonisolated private static func friendlyNotaryError(_ output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("invalid credentials") || lower.contains("http status code: 401") {
            return """
            Apple rejected the notarization credential.

            Check these three things:
            1. Apple ID Email must be the Apple Developer account for this Team ID.
            2. Password must be a newly generated app-specific password from account.apple.com > Sign-In and Security > App-Specific Passwords.
            3. Paste the full generated password, including hyphens if Apple shows them.

            Do not use your normal Apple ID password here.
            """
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "notarytool failed without a message." : trimmed
    }

    nonisolated private static func failure(from error: Error) -> SetupFailure {
        let message = error.localizedDescription
        let lower = message.lowercased()

        if lower.contains("apple rejected the notarization credential") {
            return SetupFailure(
                title: "Apple rejected the notarization credential",
                message: "The Apple ID email and password were not accepted by Apple's notarization service.",
                recovery: "Generate a new app-specific password inside your Apple Account, then try setup again. Do not use your normal Apple ID password or a password generated only by your password manager.",
                details: message,
                actionTitle: "Open Apple Account",
                actionURL: URL(string: "https://account.apple.com")
            )
        }

        if lower.contains("already exists") {
            return SetupFailure(
                title: "The local env file already exists",
                message: message,
                recovery: "Go back, review the env file path, then enable Replace existing env file if you want Publisher Setup to overwrite it.",
                details: message,
                actionTitle: nil,
                actionURL: nil
            )
        }

        return SetupFailure(
            title: "Publisher setup did not finish",
            message: "The setup step failed before this Mac was ready to publish.",
            recovery: "Copy the details below, fix the named issue, then try setup again.",
            details: message,
            actionTitle: nil,
            actionURL: nil
        )
    }

    nonisolated private static func publishFailure(from error: Error, log: String) -> SetupFailure {
        let details = log.isEmpty ? error.localizedDescription : log
        return SetupFailure(
            title: "Release publishing stopped",
            message: "The app could not finish building, signing, or notarizing the release artifact.",
            recovery: "Copy the log below. Fix the first failed command it names, then return to Publisher Setup and run publishing again.",
            details: details,
            actionTitle: nil,
            actionURL: nil
        )
    }

    nonisolated private static func runReleaseStep(
        title: String,
        command: String,
        envFile: String,
        log: String,
        update: @escaping (String, String) -> Void
    ) throws -> (log: String, status: Int32) {
        let shell = "source \(shellQuote(envFile)) && \(command)"
        let lock = NSLock()
        var combinedLog = log + "\n$ \(command)\n"
        update(title, combinedLog)

        let status = try runStreamingCommand("/bin/bash", ["-lc", shell]) { chunk in
            lock.lock()
            combinedLog += chunk
            let snapshot = combinedLog
            lock.unlock()
            update(title, snapshot)
        }

        lock.lock()
        if !combinedLog.hasSuffix("\n") {
            combinedLog += "\n"
        }
        let finalLog = combinedLog
        lock.unlock()
        update(title, finalLog)
        return (finalLog, status)
    }

    nonisolated private static func requireReleaseStepSuccess(_ title: String, status: Int32) throws {
        guard status == 0 else {
            throw NSError(
                domain: "PublisherSetup",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "\(title) failed with exit code \(status)."]
            )
        }
    }

    nonisolated private static func runStreamingCommand(
        _ executable: String,
        _ arguments: [String],
        onOutput: @escaping (String) -> Void
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let handle = output.fileHandleForReading
        process.standardOutput = output
        process.standardError = output
        handle.readabilityHandler = { stream in
            let data = stream.availableData
            guard !data.isEmpty else {
                return
            }
            onOutput(String(data: data, encoding: .utf8) ?? "")
        }

        try process.run()
        process.waitUntilExit()
        handle.readabilityHandler = nil

        let remaining = handle.readDataToEndOfFile()
        if !remaining.isEmpty {
            onOutput(String(data: remaining, encoding: .utf8) ?? "")
        }

        return process.terminationStatus
    }

    nonisolated private static func writeEnvFile(path: String, identity: String, profileName: String, replaceExisting: Bool) throws {
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) && !replaceExisting {
            throw NSError(
                domain: "PublisherSetup",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(path) already exists. Enable Replace existing env file."]
            )
        }

        let body = """
        # Local publisher release environment. Do not commit.
        # Generated by scripts/publisher_setup.swift
        export CT_SIGN_IDENTITY=\(shellQuote(identity))
        export APPLE_SIGNING_IDENTITY="$CT_SIGN_IDENTITY"
        export CT_NOTARY_KEYCHAIN_PROFILE=\(shellQuote(profileName))

        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }
}

func parseIdentities(_ output: String) -> [SigningIdentity] {
    var seen: Set<String> = []
    var identities: [SigningIdentity] = []
    let pattern = #"\"(Developer ID Application: .*\(([A-Z0-9]{10})\))\""#
    let regex = try? NSRegularExpression(pattern: pattern)

    for line in output.split(separator: "\n") {
        let text = String(line)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let nameRange = Range(match.range(at: 1), in: text),
              let teamRange = Range(match.range(at: 2), in: text)
        else {
            continue
        }
        let name = String(text[nameRange])
        guard seen.insert(name).inserted else {
            continue
        }
        identities.append(SigningIdentity(id: name, name: name, teamId: String(text[teamRange])))
    }

    return identities.sorted { $0.name < $1.name }
}

func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

func readPipe(_ pipe: Pipe) -> String {
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func runCommand(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus, output: readPipe(stdout) + readPipe(stderr))
}

/// Finds the last "$ " command line in a log: the command that was running when a release
/// step failed, since no later step ever starts. Used to render the first-failed-command
/// highlight (design spec §4.4) without touching the underlying CLI/log-producing logic.
func lastCommandMarkerIndex(_ text: String) -> String.Index? {
    if text.hasPrefix("$ ") {
        return text.startIndex
    }
    var lastIndex: String.Index?
    var searchStart = text.startIndex
    while let range = text.range(of: "\n$ ", range: searchStart..<text.endIndex) {
        lastIndex = text.index(after: range.lowerBound)
        searchStart = range.upperBound
    }
    return lastIndex
}

// MARK: - View

struct PublisherSetupView: View {
    @StateObject private var model = PublisherSetupModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            RoadmapSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } detail: {
            Group {
                switch model.phase {
                case .welcome:
                    welcomeView
                case .prerequisites:
                    prerequisitesView
                case .guide(let guide):
                    guideView(guide)
                case .identity:
                    identityView
                case .trustVerify:
                    trustVerifyView
                case .form:
                    formView
                case .success(let success):
                    preBuildReviewView(success)
                case .publishing:
                    publishingView
                case .published(let artifact):
                    handoffView(artifact)
                case .failure(let failure):
                    failureView(failure)
                }
            }
            .id(phaseIdentity)
            .transition(stepTransition)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: phaseIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 620, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Kick off the identity scan after first render instead of from the model's
            // init(): running it here means it fires after the AttributeGraph's first
            // layout pass has finished, and refreshIdentities() itself hops off the main
            // thread for the actual subprocess call.
            model.refreshIdentities()
        }
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    /// A stable string identity per phase, used to drive step transitions.
    private var phaseIdentity: String {
        switch model.phase {
        case .welcome: return "welcome"
        case .prerequisites: return "prerequisites"
        case .guide(let guide): return "guide-\(guide.rawValue)"
        case .identity: return "identity"
        case .trustVerify: return "trustVerify"
        case .form: return "form"
        case .success: return "success"
        case .publishing: return "publishing"
        case .published: return "published"
        case .failure: return "failure"
        }
    }

    // MARK: Welcome (NEW)

    @ViewBuilder
    private var welcomeHeroImage: some View {
        if let brandIcon = PublisherSetupModel.loadBrandIcon() {
            Image(nsImage: brandIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .accessibilityLabel("Copilot Control Tower")
        } else {
            Image(systemName: "checkmark.seal")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 48))
                .foregroundColor(Color(nsColor: .systemBlue))
                .accessibilityHidden(true)
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    welcomeHeroImage

                    VStack(spacing: 12) {
                        Text("Welcome, Publisher.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .labelColor))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Copilot Control Tower is the always-on app that keeps everyone's Copilot healthy and self-healing. You're here to produce its release: the signed, notarized build that admins deploy and users can trust. You're the first link in the chain, and nothing downstream works until a trusted release exists.")
                            .font(.body)
                            .lineSpacing(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    sectionCard("Why this step matters") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("A release only earns everyone's trust once, at the source: here.")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)

                            welcomeInfoRow(symbol: "checkmark.seal", text: "Apple only runs a signed, notarized app without warnings. Your signature is the root of trust the whole ecosystem inherits.")
                            welcomeInfoRow(symbol: "building.2", text: "It lets an admin deploy Control Tower to a fleet silently, with no scary prompts for anyone.")
                            welcomeInfoRow(symbol: "arrow.triangle.2.circlepath", text: "It lets every user receive safe, automatic updates for the life of the product.")
                        }
                    }

                    sectionCard("What you'll do here") {
                        VStack(alignment: .leading, spacing: 14) {
                            welcomeInfoRow(symbol: "key", text: "Set up your Apple signing credentials. We'll walk you through each one.")
                            welcomeInfoRow(symbol: "checkmark.shield", text: "Verify your certificate is trusted and ready to sign.")
                            welcomeInfoRow(symbol: "shippingbox", text: "Build, sign, and notarize in one click, then hand the result to your Admin.")
                        }
                    }

                    Text("You hold release-signing authority only. This app never touches a fleet, an organization's content, or anyone's personal data.")
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
                    model.showPrerequisites()
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

    private func welcomeInfoRow(symbol: String, text: String) -> some View {
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

    // MARK: Prerequisites

    private var prerequisitesView: some View {
        stepShell(
            eyebrow: "Before You Begin",
            title: "What Apple needs from you",
            intro: "Open any item below for step-by-step instructions. This checklist exists so you can understand what you're holding, and why it matters, before entering any credentials."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(PublisherGuide.allCases.enumerated()), id: \.element) { index, guide in
                    prerequisiteRow(guide)
                    if index < PublisherGuide.allCases.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            calloutBlock(
                "Publisher Setup reads the Developer ID identity already installed on this Mac, stores one notarization profile in your Keychain through Apple's notarytool, and writes a local, git-ignored env file for this repo. It does not create Apple credentials and never writes Apple passwords into the repo.",
                symbol: "info.circle"
            )
        } leadingActions: {
            Button {
                model.goWelcome()
            } label: {
                Text("Back")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        } primaryAction: {
            Button {
                model.goIdentity()
            } label: {
                Text("Continue")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func prerequisiteRow(_ guide: PublisherGuide) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: guide.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(nsColor: .systemBlue))
                .imageScale(.large)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.checklistText)
                    .font(.body.weight(.medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Text(guide.why)
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                model.showGuide(guide)
            } label: {
                Text("Learn More")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Prerequisite guide (teach step)

    private func guideView(_ guide: PublisherGuide) -> some View {
        let numeral = (PublisherGuide.allCases.firstIndex(of: guide) ?? 0) + 1
        return stepShell(
            eyebrow: "Prerequisite \(numeral) of \(PublisherGuide.allCases.count)",
            title: guide.title,
            intro: guide.why
        ) {
            sectionCard("How to check this") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        numberedStep(index + 1, step)
                    }
                }
            }

            if guide == .certificate {
                sectionCard("Useful verification command") {
                    codeBlock(
                        #"security find-identity -v -p codesigning | grep "Developer ID Application""#,
                        minHeight: 60,
                        copyLabel: "Copy Command"
                    )
                }
            }

            if guide == .intermediate {
                calloutBlock(
                    "Don't use Keychain's \"Always Trust\" here. It only hides the problem on this Mac and won't make your release trusted anywhere else. Install Apple's Developer ID - G2 intermediate instead.",
                    symbol: "hand.raised"
                )
            }
        } leadingActions: {
            Button {
                model.showPrerequisites()
            } label: {
                Text("Back to Checklist")
            }
            .buttonStyle(.bordered)

            if let title = guide.actionTitle, let url = guide.actionURL {
                Button {
                    model.open(url)
                } label: {
                    Label(title, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        } primaryAction: {
            Button {
                model.goIdentity()
            } label: {
                Text("Continue")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Signing identity (verify step)

    private var identityView: some View {
        stepShell(
            eyebrow: "Step 3 of 7",
            title: "Signing identity",
            intro: "Publisher Setup looks for a Developer ID Application certificate already installed on this Mac, then extracts the Team ID that Admin will need later."
        ) {
            if model.identities.isEmpty {
                verifyResultCard(
                    symbol: "exclamationmark.shield.fill",
                    tint: Color(nsColor: .systemOrange),
                    title: "No Developer ID Application certificate on this Mac.",
                    accessibilityLabel: "Needs attention: no signing identity found"
                ) {
                    Text(model.status)
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(nsColor: .systemGreen))
                            .imageScale(.large)
                            .accessibilityHidden(true)
                        Text("Signing identity found.")
                            .font(.headline)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Button {
                            model.refreshIdentities()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh signing identities")
                        .accessibilityLabel("Refresh")
                    }

                    if model.identities.count > 1 {
                        Picker("", selection: $model.selectedIdentityId) {
                            ForEach(model.identities) { identity in
                                Text(identity.name).tag(identity.id)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Choose signing identity")
                    } else if let only = model.identities.first {
                        Text(only.name)
                            .font(.body)
                            .foregroundColor(Color(nsColor: .labelColor))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "number")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .accessibilityHidden(true)
                            Text(model.selectedIdentity?.teamId ?? "Unavailable")
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(Color(nsColor: .labelColor))
                                .textSelection(.enabled)
                                .accessibilityLabel("Team ID \(model.selectedIdentity?.teamId ?? "unavailable")")
                        }
                        Text("Extracted automatically. You'll hand this to Admin later.")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } leadingActions: {
            Button {
                model.showPrerequisites()
            } label: {
                Text("Back")
            }
            .buttonStyle(.bordered)

            if model.identities.isEmpty {
                Button {
                    model.showGuide(.certificate)
                } label: {
                    Text("Open Certificate Guide")
                }
                .buttonStyle(.bordered)
            }
        } primaryAction: {
            Button {
                if model.identities.isEmpty {
                    model.refreshIdentities()
                } else {
                    model.goTrustVerify()
                }
            } label: {
                Text(model.identities.isEmpty ? "Recheck" : "Continue")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.identities.isEmpty == false && model.selectedIdentity == nil)
        }
    }

    // MARK: Cert-trust verify (NEW)

    private var trustVerifyView: some View {
        stepShell(
            eyebrow: "Step 4 of 7",
            title: "Certificate trust",
            intro: "This is the single most common stranding point. Publisher Setup checks that your certificate has its private key and chains to a trusted anchor before you go any further."
        ) {
            switch model.trustState {
            case .verifying:
                verifyingCard("Checking this certificate's key and trust chain…")
            case .trusted:
                verifyResultCard(
                    symbol: "checkmark.shield.fill",
                    tint: Color(nsColor: .systemGreen),
                    title: "This certificate is trusted and ready to sign.",
                    accessibilityLabel: "Verified: certificate trusted and ready to sign"
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        checklistItem("Private key present")
                        checklistItem("Chain trusted")
                    }
                }
            case .untrustedFixable:
                verifyResultCard(
                    symbol: "exclamationmark.shield.fill",
                    tint: Color(nsColor: .systemOrange),
                    title: "macOS doesn't fully trust this certificate yet.",
                    accessibilityLabel: "Needs attention: certificate not yet trusted"
                ) {
                    Text("The usual cause is a missing Developer ID – G2 intermediate. Installing Apple's intermediate certificate usually completes the chain.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    calloutBlock(
                        "Don't use Keychain's \"Always Trust\". It hides the problem locally and won't make your release trusted on other Macs. Install the Developer ID - G2 intermediate instead.",
                        symbol: "hand.raised"
                    )
                }
            case .missingKey:
                verifyResultCard(
                    symbol: "xmark.shield.fill",
                    tint: Color(nsColor: .systemRed),
                    title: "This certificate has no private key on this Mac.",
                    accessibilityLabel: "Failed: certificate has no private key"
                ) {
                    Text("You'll need to recreate the certificate from a CSR generated on this Mac. A Developer ID certificate can't be exported or reused without the key that created it.")
                        .font(.body)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } leadingActions: {
            Button {
                model.goIdentity()
            } label: {
                Text("Back")
            }
            .buttonStyle(.bordered)

            if model.trustState == .untrustedFixable || model.trustState == .missingKey {
                Button {
                    model.verifyCertTrust()
                } label: {
                    Text("Re-verify")
                }
                .buttonStyle(.bordered)
            }
        } primaryAction: {
            switch model.trustState {
            case .verifying:
                Button {} label: { Text("Checking…") }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            case .trusted:
                Button {
                    model.beginSetup()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .untrustedFixable:
                Button {
                    model.showGuide(.intermediate)
                } label: {
                    Label("Open Apple Certificate Authority", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            case .missingKey:
                Button {
                    model.showGuide(.certificate)
                } label: {
                    Text("Open Certificate Guide")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if model.trustState == .verifying {
                model.verifyCertTrust()
            }
        }
    }

    // MARK: Notary + release config

    private var formView: some View {
        stepShell(
            eyebrow: "Step 5 of 7",
            title: "Notary & release config",
            intro: "Store a reusable notarization profile in your Keychain and write this repo's local, git-ignored release settings."
        ) {
            sectionCard("Notary credential") {
                Text("Stored in your Keychain; the password goes only to Apple's tool, never to this repo.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)

                formFieldRow("Apple ID Email") {
                    TextField("you@example.com", text: $model.appleId)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.skipNotary)
                } caption: {
                    "The Apple Developer account email for the team shown earlier."
                }

                formFieldRow("Profile") {
                    TextField("ct-notary", text: $model.profileName)
                        .textFieldStyle(.roundedBorder)
                } caption: {
                    "A local Keychain profile name. Release scripts reuse this name instead of asking for the Apple credential again."
                }

                formFieldRow("Password") {
                    secureFieldRow()
                } caption: {
                    model.skipNotary
                        ? "Disabled while Skip notarization is on."
                        : "An app-specific password, not your Apple ID password. Sent only to xcrun notarytool store-credentials, then cleared from this form."
                }

                Toggle("Skip notarization", isOn: $model.skipNotary)
                    .toggleStyle(.switch)
                Text(model.skipNotary ? "The artifact won't be notarized. Only do this to test the build." : "Notarization lets macOS trust the release before it runs on another Mac.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }

            sectionCard("Release config") {
                formFieldRow("Env file") {
                    TextField(".env.release.local", text: $model.envFile)
                        .textFieldStyle(.roundedBorder)
                } caption: {
                    "Non-secret settings, git-ignored, owner-only permissions."
                }

                Toggle("Replace existing file", isOn: $model.replaceExisting)
                    .toggleStyle(.switch)
            }

            if model.status.localizedCaseInsensitiveContains("failed")
                || model.status.localizedCaseInsensitiveContains("enter")
                || model.status.localizedCaseInsensitiveContains("choose") {
                Text(model.status)
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } leadingActions: {
            Button {
                model.goTrustVerify()
            } label: {
                Text("Back")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            HStack(spacing: 8) {
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.setup()
                } label: {
                    Text(model.isRunning ? "Setting up…" : "Set Up Publisher Machine")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRunning || model.identities.isEmpty)
            }
        }
    }

    private func secureFieldRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "key.horizontal")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .accessibilityHidden(true)
            SecureField("App-specific password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .disabled(model.skipNotary)
        }
    }

    // MARK: Pre-build review (formerly "success")

    private func preBuildReviewView(_ success: SetupSuccess) -> some View {
        let commands = publisherCommands(envFile: success.envFile)

        return stepShell(
            eyebrow: "Step 5 → 6",
            title: "Ready to build the release.",
            intro: "This Mac is configured. Publisher Setup can now build, sign, notarize, and staple the release artifact. This may take several minutes."
        ) {
            sectionCard("What was configured") {
                summaryRow("Signing identity", success.identity)
                summaryRow("Team ID", model.selectedIdentity?.teamId ?? "Unavailable")
                summaryRow("Notary profile", success.notarySkipped ? "Skipped" : success.profileName)
                summaryRow("Env file", success.envFile)
            }

            calloutBlock(
                "Build, Sign & Notarize runs npm run tauri build, signs the app with your Developer ID certificate, submits it to Apple for notarization, then staples the result. Keep this window open while it runs.",
                symbol: "hammer"
            )
        } leadingActions: {
            Button {
                model.editSetup()
            } label: {
                Text("Edit Setup")
            }
            .buttonStyle(.bordered)

            Button {
                model.copy(commands, label: "Commands copied")
            } label: {
                Label("Copy Manual Commands", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            Button {
                model.publish(success)
            } label: {
                Text("Build, Sign & Notarize")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Building / live log

    private var publishingView: some View {
        stepShell(
            eyebrow: "Step 6 of 7",
            title: model.publishStep.isEmpty ? "Building Control Tower" : model.publishStep,
            intro: "Publisher Setup is running the release path. Keep this window open while it builds, signs, notarizes, and staples the artifact."
        ) {
            HStack(spacing: 16) {
                stepChip("Build", symbol: "hammer", state: chipState(for: "Build"))
                stepChip("Sign", symbol: "signature", state: chipState(for: "Sign"))
                stepChip("Notarize", symbol: "paperplane", state: chipState(for: "Notarize"))
            }

            sectionCard("Live log") {
                liveLogBlock(model.publishLog.isEmpty ? "Starting…" : model.publishLog, minHeight: 220, highlightFailure: false, copyLabel: "Copy Log")
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Building…")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    private func chipState(for name: String) -> StepChipState {
        let step = model.publishStep
        let order = ["Build", "Sign", "Notarize"]
        guard let currentIndex = order.firstIndex(where: { step.localizedCaseInsensitiveContains($0) }) else {
            return .pending
        }
        guard let thisIndex = order.firstIndex(of: name) else {
            return .pending
        }
        if thisIndex < currentIndex {
            return .done
        } else if thisIndex == currentIndex {
            return .active
        }
        return .pending
    }

    private enum StepChipState {
        case pending, active, done
    }

    private func stepChip(_ title: String, symbol: String, state: StepChipState) -> some View {
        HStack(spacing: 6) {
            switch state {
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            case .active:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
            }
            Text(title)
                .font(.callout.weight(state == .active ? .semibold : .regular))
                .foregroundColor(state == .pending ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: .labelColor))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(state == .done ? "done" : state == .active ? "in progress" : "not started")")
    }

    // MARK: Success / structured handoff

    private func handoffView(_ artifact: PublishArtifact) -> some View {
        let handoff = model.handoffText(for: artifact)

        return stepShell(
            eyebrow: "Step 7 of 7",
            title: "The release is signed and ready for Admin.",
            intro: "The publisher job is complete: the app was built, signed" + (artifact.notarizedSkipped ? "" : ", notarized,") + " and stapled."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(nsColor: .systemGreen))
                        .imageScale(.large)
                        .accessibilityHidden(true)
                    Text("Publisher → Admin handoff")
                        .font(.headline)
                        .foregroundColor(Color(nsColor: .labelColor))
                }

                codeBlock(handoff, minHeight: 160, copyLabel: "Copy Handoff", accessibilityLabel: "Handoff block")

                if artifact.notarizedSkipped {
                    calloutBlock("Notarization was skipped for this build. This artifact will not be trusted by macOS Gatekeeper on another Mac.", symbol: "exclamationmark.triangle")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            sectionCard("What was produced") {
                revealRow("App", artifact.appPath)
                revealRow("DMG", artifact.dmgPath)
            }

            DisclosureGroup("Show build log") {
                liveLogBlock(artifact.log, minHeight: 160, highlightFailure: false, copyLabel: "Copy Publishing Log")
                    .padding(.top, 8)
            }
            .font(.callout)

            calloutBlock(
                "Next role: Admin deploys this trusted artifact: configures org policy, generates the MDM profile, and rolls out to managed Macs. Your job as publisher is done.",
                symbol: "arrow.right.circle"
            )
        } leadingActions: {
            Button {
                model.reveal(artifact.appPath)
            } label: {
                Label("Reveal Artifacts", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.bordered)
        } primaryAction: {
            Button {
                if model.copiedMessage == "Handoff copied" {
                    NSApplication.shared.terminate(nil)
                } else {
                    model.copy(handoff, label: "Handoff copied")
                }
            } label: {
                Text(model.copiedMessage == "Handoff copied" ? "Done" : "Copy Handoff")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Copy handoff block")
        }
    }

    private func revealRow(_ label: String, _ path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 48, alignment: .leading)
            Text(path)
                .font(.body.monospaced())
                .foregroundColor(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.reveal(path)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(label) in Finder")
        }
    }

    // MARK: Failure (inline, contextual)

    private func failureView(_ failure: SetupFailure) -> some View {
        stepShell(
            eyebrow: "Publisher Setup Stopped",
            title: failure.title,
            intro: failure.message
        ) {
            sectionCard("What to do next") {
                Text(failure.recovery)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if let title = failure.actionTitle, let url = failure.actionURL {
                    Button {
                        model.open(url)
                    } label: {
                        Label(title, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            sectionCard("Details") {
                Text("Copy this if you need to search, retry, or hand the failure to someone else.")
                    .font(.callout)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                liveLogBlock(failure.details, minHeight: 140, highlightFailure: model.failureOrigin == .publish, copyLabel: "Copy Details")
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
                model.retryAfterFailure()
            } label: {
                Text("Try Again")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .headerTint(Color(nsColor: .systemRed))
    }

    // MARK: Shared shell + components

    private func stepShell<Content: View, Leading: View, Trailing: View>(
        eyebrow: String,
        title: String,
        intro: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) -> StepShell<Content, Leading, Trailing> {
        StepShell(
            eyebrow: eyebrow,
            title: title,
            intro: intro,
            copiedMessage: model.copiedMessage,
            content: content,
            leadingActions: leadingActions,
            primaryAction: primaryAction
        )
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
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

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .separatorColor).opacity(0.35))
                .clipShape(Circle())
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checklistItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundColor(Color(nsColor: .systemGreen))
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.body.monospaced())
                .foregroundColor(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
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

    private func formFieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content, caption: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            content()
            Text(caption())
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func codeBlock(_ value: String, minHeight: CGFloat, copyLabel: String, accessibilityLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(value)
                    .font(.body.monospaced())
                    .foregroundColor(Color(nsColor: .labelColor))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: max(minHeight, 220), alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(accessibilityLabel ?? "Code block")

            Button {
                model.copy(value, label: copyLabel == "Copy Handoff" ? "Handoff copied" : "Copied")
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func liveLogBlock(_ text: String, minHeight: CGFloat, highlightFailure: Bool, copyLabel: String) -> some View {
        let markerIndex = highlightFailure ? lastCommandMarkerIndex(text) : nil

        return VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let markerIndex, markerIndex > text.startIndex {
                            Text(String(text[text.startIndex..<markerIndex]))
                                .font(.body.monospaced())
                                .foregroundColor(Color(nsColor: .labelColor))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let markerIndex {
                            Text(String(text[markerIndex...]))
                                .font(.body.monospaced())
                                .foregroundColor(Color(nsColor: .labelColor))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .systemRed).opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Color(nsColor: .systemRed)).frame(width: 3)
                                }
                                .id("failureMarker")
                        } else {
                            Text(text.isEmpty ? "Starting…" : text)
                                .font(.body.monospaced())
                                .foregroundColor(Color(nsColor: .labelColor))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .onAppear {
                    proxy.scrollTo(markerIndex != nil ? "failureMarker" : "bottom", anchor: .bottom)
                }
                .onChange(of: text) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(markerIndex != nil ? "failureMarker" : "bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Build log")

            Button {
                model.copy(text, label: "Log copied")
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func publisherCommands(envFile: String) -> String {
        """
        source \(envFile)
        PATH="/usr/bin:$PATH" CC=/usr/bin/cc npm run tauri build
        ./scripts/sign.sh "src-tauri/target/release/bundle/macos/Copilot Control Tower.app"
        DMG="$(ls -t src-tauri/target/release/bundle/dmg/*.dmg | head -n1)"
        ./scripts/notarize.sh "src-tauri/target/release/bundle/macos/Copilot Control Tower.app" "$DMG"
        """
    }
}

/// Shared step anatomy: eyebrow → title → intro → content → pinned footer action bar
/// (design spec §2.1). Kept as its own view (rather than a function returning `some View`)
/// so a `.headerTint` modifier can recolor the eyebrow for the failure screen.
struct StepShell<Content: View, Leading: View, Trailing: View>: View {
    let eyebrow: String
    let title: String
    let intro: String?
    let copiedMessage: String
    @ViewBuilder let content: Content
    @ViewBuilder let leadingActions: Leading
    @ViewBuilder let primaryAction: Trailing
    var tint: Color = Color(nsColor: .systemBlue)

    init(
        eyebrow: String,
        title: String,
        intro: String?,
        copiedMessage: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder primaryAction: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.intro = intro
        self.copiedMessage = copiedMessage
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
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                leadingActions
                if !copiedMessage.isEmpty {
                    Text(copiedMessage)
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .transition(.opacity)
                }
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

/// The persistent roadmap sidebar always shows all seven stages with done/current/upcoming
/// state (design spec §2.1, §4.8). Rendered inside a `List` with `.sidebar` style so it
/// automatically picks up the system sidebar material/vibrancy.
struct RoadmapSidebar: View {
    @ObservedObject var model: PublisherSetupModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(Color(nsColor: .systemBlue))
                    Text("Publisher Setup")
                        .font(.headline)
                        .foregroundColor(Color(nsColor: .labelColor))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                ForEach(RoadmapStage.allCases) { stage in
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

    private func roadmapRow(_ stage: RoadmapStage) -> some View {
        let current = model.currentRoadmapStage
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
            .background(
                isCurrent
                    ? Color(nsColor: .controlAccentColor).opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isDone)
        .opacity(isDone || isCurrent ? 1.0 : 0.5)
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(RoadmapStage.allCases.count), \(stage.title), \(statusWord)")
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

struct PublisherSetupApp: App {
    var body: some Scene {
        WindowGroup("Publisher Setup") {
            PublisherSetupView()
        }
        .defaultSize(width: 960, height: 720)
        .windowStyle(.titleBar)
    }
}

PublisherSetupApp.main()
