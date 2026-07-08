#!/usr/bin/env swift
import SwiftUI
import Foundation

struct SigningIdentity: Identifiable, Hashable {
    let id: String
    let name: String
    let teamId: String
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum SetupPhase {
    case prerequisites
    case guide(PublisherGuide)
    case form
    case success(SetupSuccess)
    case failure(SetupFailure)
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
}

struct SetupFailure {
    let title: String
    let message: String
    let recovery: String
    let details: String
    let actionTitle: String?
    let actionURL: URL?
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
    @Published var phase: SetupPhase = .prerequisites
    @Published var copiedMessage: String = ""

    var selectedIdentity: SigningIdentity? {
        identities.first { $0.id == selectedIdentityId }
    }

    init() {
        refreshIdentities()
    }

    func refreshIdentities() {
        do {
            let output = try runCommand("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]).output
            let parsed = parseIdentities(output)
            identities = parsed
            if selectedIdentityId.isEmpty || !parsed.contains(where: { $0.id == selectedIdentityId }) {
                selectedIdentityId = parsed.first?.id ?? ""
            }
            status = parsed.isEmpty
                ? "No Developer ID Application certificate was found. Install the certificate and the Developer ID - G2 intermediate first."
                : "Found \(parsed.count) Developer ID Application signing identity\(parsed.count == 1 ? "" : "ies")."
        } catch {
            identities = []
            selectedIdentityId = ""
            status = "Could not inspect signing identities: \(error.localizedDescription)"
        }
    }

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
                    self.phase = .success(
                        SetupSuccess(envFile: env, profileName: profile, identity: identity.name)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.password = ""
                    self.isRunning = false
                    self.status = "Setup failed."
                    self.phase = .failure(Self.failure(from: error))
                }
            }
        }
    }

    func editSetup() {
        copiedMessage = ""
        phase = .form
    }

    func showGuide(_ guide: PublisherGuide) {
        copiedMessage = ""
        phase = .guide(guide)
    }

    func showPrerequisites() {
        copiedMessage = ""
        phase = .prerequisites
    }

    func beginSetup() {
        copiedMessage = ""
        phase = .form
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

struct PublisherSetupView: View {
    @StateObject private var model = PublisherSetupModel()

    var body: some View {
        Group {
            switch model.phase {
            case .prerequisites:
                prerequisitesView
            case .guide(let guide):
                guideView(guide)
            case .form:
                formView
            case .success(let success):
                successView(success)
            case .failure(let failure):
                failureView(failure)
            }
        }
        .frame(minWidth: 860, idealWidth: 1040, minHeight: 900, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                setupContextSection
                signingSection
                notarizationSection
                envSection
                formActions
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var prerequisitesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Publisher Setup")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text("You are preparing the Mac that will publish Control Tower releases. We will set up signing, notarization, and the local release environment after these Apple prerequisites are in place.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("Before You Continue") {
                    helper("Open any item for step-by-step instructions. This checklist exists so a publisher can understand what they are holding and why it matters before entering credentials.")
                    ForEach(PublisherGuide.allCases) { guide in
                        prerequisiteRow(guide)
                    }
                }

                section("What This Setup Will Do") {
                    helper("Publisher Setup reads the Developer ID identity already installed on this Mac, stores one notarization profile in your Keychain through Apple's notarytool, and writes a local ignored env file for this repo. It does not create Apple credentials and it does not write Apple passwords into the repo.")
                }

                HStack(spacing: 12) {
                    Button {
                        model.beginSetup()
                    } label: {
                        Text("Continue To Setup")
                            .foregroundColor(.white)
                            .frame(width: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .foregroundColor(Color(nsColor: .controlTextColor))
                            .frame(width: 96)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func guideView(_ guide: PublisherGuide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Publisher Prerequisite")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(nsColor: .systemBlue))
                        .textCase(.uppercase)
                    Text(guide.title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text(guide.why)
                        .font(.system(size: 14))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("How To Check This") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            numberedStep(index + 1, step)
                        }
                    }
                }

                if guide == .certificate {
                    section("Useful Verification Command") {
                        commandBlock(
                            #"security find-identity -v -p codesigning | grep "Developer ID Application""#,
                            copyLabel: "Copy Command"
                        )
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        model.showPrerequisites()
                    } label: {
                        Text("Back To Checklist")
                            .foregroundColor(Color(nsColor: .controlTextColor))
                            .frame(width: 150)
                    }
                    .buttonStyle(.bordered)

                    if let title = guide.actionTitle, let url = guide.actionURL {
                        Button {
                            model.open(url)
                        } label: {
                            Text(title)
                                .foregroundColor(.white)
                                .frame(width: 180)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        model.beginSetup()
                    } label: {
                        Text("Continue To Setup")
                            .foregroundColor(Color(nsColor: .controlTextColor))
                            .frame(width: 160)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Publisher Setup")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text("Configure this Mac to sign, notarize, and build Control Tower release artifacts. This is release-owner tooling, not the Admin deployment flow.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signingSection: some View {
        section("Signing") {
            field("Certificate") {
                HStack(spacing: 10) {
                    Picker("", selection: $model.selectedIdentityId) {
                        if model.identities.isEmpty {
                            Text("No Developer ID Application identity found").tag("")
                        } else {
                            ForEach(model.identities) { identity in
                                Text(identity.name).tag(identity.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        model.refreshIdentities()
                    } label: {
                        Text("Refresh")
                            .foregroundColor(Color(nsColor: .controlTextColor))
                            .frame(width: 72)
                    }
                    .buttonStyle(.bordered)
                }
            }

            field("Team ID") {
                Text(model.selectedIdentity?.teamId ?? "Unavailable")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
        }
    }

    private var setupContextSection: some View {
        section("You Are Ready To Configure This Mac") {
            helper("Use the Apple Developer account email for this Team ID and the Apple-generated app-specific password you prepared. If any prerequisite is unclear, go back to the checklist before submitting.")
            Button {
                model.showPrerequisites()
            } label: {
                Text("Review Prerequisites")
                    .foregroundColor(Color(nsColor: .controlTextColor))
                    .frame(width: 160)
            }
            .buttonStyle(.bordered)
        }
    }

    private var notarizationSection: some View {
        section("Notarization") {
            helper("Apple uses notarization to check the signed app before macOS will trust it. This setup stores a reusable notary profile in your Mac Keychain; the password is sent only to Apple's notarytool for that storage step and is not written to this repo.")

            field("Apple ID Email") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("you@example.com", text: $model.appleId)
                        .textFieldStyle(.roundedBorder)
                    caption("The Apple Developer account email for the team shown above.")
                }
            }

            field("Profile") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        TextField("ct-notary", text: $model.profileName)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Skip notary", isOn: $model.skipNotary)
                            .toggleStyle(.checkbox)
                            .frame(width: 130, alignment: .leading)
                    }
                    caption("A local Keychain profile name. Release scripts use this name later instead of asking for the Apple credential again.")
                }
            }

            field("Password") {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("App-specific password", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.skipNotary)
                    caption("Use an Apple-generated app-specific password from account.apple.com, not your normal Apple ID password and not a password-manager generated password. It is passed to xcrun notarytool store-credentials, saved by Apple's tool in Keychain, then cleared from this form.")
                }
            }
        }
    }

    private var envSection: some View {
        section("Local Env") {
            helper("This file stores non-secret release settings for this repo, such as the signing identity and Keychain profile name. It is ignored by git and written with owner-only permissions.")

            field("Env file") {
                TextField(".env.release.local", text: $model.envFile)
                    .textFieldStyle(.roundedBorder)
            }

            field("") {
                Toggle("Replace existing env file", isOn: $model.replaceExisting)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var formActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    model.setup()
                } label: {
                    Text(model.isRunning ? "Setting Up..." : "Set Up Publisher Machine")
                        .foregroundColor(.white)
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRunning || model.identities.isEmpty)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .foregroundColor(Color(nsColor: .controlTextColor))
                        .frame(width: 96)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }

            Text(model.status)
                .font(.system(size: 12))
                .foregroundColor(model.status.localizedCaseInsensitiveContains("failed") ? .red : Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
    }

    private func successView(_ success: SetupSuccess) -> some View {
        outcomeShell(
            eyebrow: "Publisher Setup Complete",
            title: "This Mac is ready to publish Control Tower artifacts",
            message: "The signing identity and notary profile are configured locally. The app-specific password has been cleared from this form; Apple's notary profile is stored in Keychain.",
            tone: .success
        ) {
            VStack(alignment: .leading, spacing: 16) {
                section("What Was Configured") {
                    summaryRow("Signing identity", success.identity)
                    summaryRow("Notary profile", success.profileName)
                    summaryRow("Local env file", success.envFile)
                }

                section("Next Publisher Step") {
                    helper("Open Terminal in this repo and run these commands. They build the app with the real system C compiler, then sign and notarize the generated artifacts.")
                    commandBlock(
                        """
                        source \(success.envFile)
                        PATH="/usr/bin:$PATH" CC=/usr/bin/cc npm run tauri build
                        ./scripts/sign.sh "src-tauri/target/release/bundle/macos/Copilot Control Tower.app"
                        ./scripts/notarize.sh "src-tauri/target/release/bundle/macos/Copilot Control Tower.app" "src-tauri/target/release/bundle/dmg/Copilot Control Tower.dmg"
                        """,
                        copyLabel: "Copy Publisher Commands"
                    )
                }

                section("After The Artifact Exists") {
                    helper("The publisher job ends when there is a signed, notarized, stapled app artifact. The next hat is Admin: configure org policy, generate the MDM profile, run preflight, and roll out to the fleet.")
                }
            }
        } footer: {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Done")
                    .foregroundColor(.white)
                    .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.editSetup()
            } label: {
                Text("Edit Setup")
                    .foregroundColor(Color(nsColor: .controlTextColor))
                    .frame(width: 120)
            }
            .buttonStyle(.bordered)
        }
    }

    private func failureView(_ failure: SetupFailure) -> some View {
        outcomeShell(
            eyebrow: "Publisher Setup Stopped",
            title: failure.title,
            message: failure.message,
            tone: .failure
        ) {
            VStack(alignment: .leading, spacing: 16) {
                section("What To Do Next") {
                    helper(failure.recovery)
                    if let title = failure.actionTitle, let url = failure.actionURL {
                        Button {
                            model.open(url)
                        } label: {
                            Text(title)
                                .foregroundColor(.white)
                                .frame(width: 180)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                section("Copyable Details") {
                    helper("Copy this if you need to search, retry, or hand the failure to someone else.")
                    commandBlock(failure.details, copyLabel: "Copy Failure Details")
                }
            }
        } footer: {
            Button {
                model.editSetup()
            } label: {
                Text("Try Again")
                    .foregroundColor(.white)
                    .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .foregroundColor(Color(nsColor: .controlTextColor))
                    .frame(width: 96)
            }
            .buttonStyle(.bordered)
        }
    }

    private enum OutcomeTone {
        case success
        case failure

        var color: Color {
            switch self {
            case .success:
                return Color(nsColor: .systemGreen)
            case .failure:
                return Color(nsColor: .systemRed)
            }
        }
    }

    private func outcomeShell<Content: View, Footer: View>(
        eyebrow: String,
        title: String,
        message: String,
        tone: OutcomeTone,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(eyebrow)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tone.color)
                        .textCase(.uppercase)

                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    content()
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            HStack(spacing: 12) {
                footer()
                if !model.copiedMessage.isEmpty {
                    Text(model.copiedMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prerequisiteRow(_ guide: PublisherGuide) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(nsColor: .systemGreen))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.checklistText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                Text(guide.why)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                model.showGuide(guide)
            } label: {
                Text("Learn More")
                    .foregroundColor(Color(nsColor: .controlTextColor))
                    .frame(width: 96)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .separatorColor).opacity(0.35))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checklistItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✓")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(nsColor: .systemGreen))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commandBlock(_ value: String, copyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 180, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                model.copy(value, label: "Copied")
            } label: {
                Text(copyLabel)
                    .foregroundColor(Color(nsColor: .controlTextColor))
                    .frame(width: 180)
            }
            .buttonStyle(.bordered)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .frame(width: 112, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity)
        }
    }
}

struct PublisherSetupApp: App {
    var body: some Scene {
        WindowGroup("Publisher Setup") {
            PublisherSetupView()
        }
        .defaultSize(width: 1040, height: 900)
        .windowStyle(.titleBar)
    }
}

PublisherSetupApp.main()
