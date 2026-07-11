//
// Copilot Control Tower — Admin mode, part 2.
//
// Continues `native/admin.swift` (read that file's header first): surfaces
// 9-16 (Handed off through the five Governance surfaces), the brief writer +
// skill materializer + verify-verb shelling (the real machine seams named in
// docs/01-architecture/admin-standup-contract.md), and `AdminWindowController`
// (the one entry point `control-tower-tray.swift` calls). Compiles into the
// same module as every other `native/*.swift` file.

import AppKit
import SwiftUI

// MARK: - AdminModel: the brief writer + skill materializer (admin-standup-
// contract.md §1 and §2.1) — REAL file I/O against the contract's paths.

extension AdminModel {
    /// The single copyable handoff line (contract §2): starts an interactive
    /// Claude Code session with the `admin-bootstrap` skill as the opening
    /// prompt, pointed at the brief's fully-resolved path (not a literal `~`,
    /// so the pasted line works regardless of the destination shell's quoting
    /// rules around tilde-expansion inside double quotes).
    var handoffCommand: String {
        "claude \"/admin-bootstrap \(AdminPaths.briefPath)\""
    }

    private func yamlQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    // `validDepartments` and `storeKindSlug` are shared, non-private
    // computed properties on `AdminModel` (native/admin.swift), also used by
    // `briefFingerprint` — no local duplicates here.

    /// Builds the exact front-matter + prose shape admin-standup-contract.md
    /// §1.2 specifies. This is legibility/collection only — the engine
    /// (`scripts/admin_bootstrap.sh`, owned elsewhere) is the sole authority
    /// that ever creates anything from it.
    func buildBriefContents() -> String {
        let depts = validDepartments
        var lines: [String] = ["---"]
        lines.append("schema_version: \"1.0\"")
        lines.append("org: \(orgSlug)")
        lines.append("harness:")
        lines.append("  - \(harness.repoToken)")
        if depts.isEmpty {
            lines.append("departments: []")
        } else {
            lines.append("departments:")
            for dept in depts { lines.append("  - \(dept.slug)") }
        }
        lines.append("store:")
        switch storeStatus {
        case .connected:
            lines.append("  status: connected")
            lines.append("  type: \(storeKindSlug)")
            lines.append("  endpoint: \(storeAddress)")
            if depts.isEmpty {
                lines.append("  team_scopes: []")
            } else {
                lines.append("  team_scopes:")
                for dept in depts {
                    let scope = storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)"
                    lines.append("    - { team: \(dept.slug), scope: \(scope) }")
                }
            }
        case .deferred, .undecided:
            lines.append("  status: deferred")
        }
        lines.append("contacts:")
        lines.append("  publisher: \(yamlQuote(contactPublisher))")
        lines.append("  admin: \(yamlQuote(contactAdmin))")
        lines.append("  point_of_contact: \(yamlQuote(contactPointOfContact))")
        lines.append("---")
        lines.append("")
        lines.append("# Standup brief for \(orgSlug)")
        lines.append("")
        lines.append("## What this describes")
        lines.append(describeSummarySentence(depts))
        lines.append("")
        lines.append("## Departments")
        if depts.isEmpty {
            lines.append("None yet.")
        } else {
            for dept in depts { lines.append("- \(dept.name)") }
        }
        lines.append("")
        lines.append("## Shared secret store")
        lines.append(storeProseSentence(depts))
        lines.append("")
        lines.append("## What this file is")
        lines.append("A plain description Claude Code reads as a starting point. It confirms it with you, then does the work. GitHub is the source of truth; the Setup check reads it fresh.")
        return lines.joined(separator: "\n") + "\n"
    }

    private func describeSummarySentence(_ depts: [DepartmentEntry]) -> String {
        let deptPart = depts.isEmpty
            ? "no departments yet"
            : "departments " + depts.map { $0.name }.joined(separator: " and ")
        let storePart = storeStatus == .connected
            ? "Its shared secret store is connected."
            : "Its shared secret store isn't connected yet."
        return "\(orgSlug), a \(harness.displayName) shop, with \(deptPart). \(storePart) This file carries no secrets and no integrations."
    }

    private func storeProseSentence(_ depts: [DepartmentEntry]) -> String {
        switch storeStatus {
        case .connected:
            let mapping = depts.map { dept -> String in
                let scope = storeScopeByDepartment[dept.id] ?? "dept/\(dept.slug)"
                return "\(dept.name) -> \(scope)"
            }.joined(separator: ", ")
            return "Connected: \(storeKind.rawValue) at \(storeAddress).\(mapping.isEmpty ? "" : " " + mapping + ".")"
        case .deferred, .undecided:
            return "Not connected yet. Connect one before your first shared integration can work."
        }
    }

    /// Writes the canonical brief (§1.4: exactly one, rewritten in place on
    /// every write) then materializes the bundled skill (§2.1), in that
    /// order — the Review surface offers the copyable command only once both
    /// succeed, per the contract's fallback story.
    func writeBriefAndMaterializeSkill() async {
        briefWriteState = .working
        let contents = buildBriefContents()
        let wrote = await AdminIO.writeFile(contents: contents, to: AdminPaths.briefPath)
        briefWriteState = wrote ? .success : .failure
        guard wrote else { return }

        skillMaterializeState = .working
        let materialized = await AdminIO.materializeSkill(
            source: AdminPaths.bundledSkillSourcePath,
            destination: AdminPaths.materializedSkillDestPath,
            enginePath: AdminPaths.enginePath
        )
        skillMaterializeState = materialized ? .success : .failure
    }
}

// MARK: - AdminModel: the verify verb (admin-standup-contract.md §3) — REAL
// shell-out to `scripts/admin_bootstrap.sh --verify --json`, rendered never
// computed. Degrades honestly if the engine or `gh` is missing.

extension AdminModel {
    func runSetupCheck() {
        Task { await performSetupCheck() }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func performSetupCheck() async {
        verifyState = .working
        verifyDegradedLine = nil
        verifyRows = []
        verifyMustFix = 0
        verifyUnknown = 0

        guard FileManager.default.fileExists(atPath: AdminPaths.enginePath) else {
            verifyDegradedLine = "I can't find the setup check engine on this Mac, so I won't guess."
            verifyUnknown = 1
            verifyState = .success
            return
        }

        let ghPresent = await ShellRunner.run("command -v gh")
        guard ghPresent.exitCode == 0 else {
            verifyDegradedLine = "GitHub's command-line tool isn't on this Mac yet, so I can't read what's really on GitHub. Install it, then run this again."
            verifyUnknown = 1
            verifyState = .success
            return
        }

        let command = "bash \(shellQuote(AdminPaths.enginePath)) --verify --brief \(shellQuote(AdminPaths.briefPath)) --json"
        let result = await ShellRunner.run(command)

        guard let payload = Self.parseVerifyPayload(result.stdout), Self.isSchemaVersionSupported(payload.schemaVersion) else {
            let honest = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            verifyDegradedLine = honest.isEmpty
                ? "Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up."
                : honest
            verifyUnknown = 1
            verifyState = .success
            return
        }

        verifyRows = payload.rows
        verifyMustFix = payload.mustFix
        verifyUnknown = payload.unknown
        verifyState = .success
    }

    static func isSchemaVersionSupported(_ version: String) -> Bool {
        version.hasPrefix("1.")
    }

    static func parseVerifyPayload(_ jsonString: String) -> (schemaVersion: String, rows: [VerifyRow], mustFix: Int, unknown: Int)? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = obj["schema_version"] as? String,
              let checksArray = obj["checks"] as? [[String: Any]],
              let summary = obj["summary"] as? [String: Any]
        else { return nil }

        let rows: [VerifyRow] = checksArray.compactMap { dict in
            guard let check = dict["check"] as? String,
                  let status = dict["status"] as? String,
                  let detail = dict["detail"] as? String
            else { return nil }
            let owner = dict["owner"] as? String ?? ""
            let fixSurface = dict["fix_surface"] as? String ?? "none"
            return VerifyRow(check: check, status: status, detail: detail, owner: owner, fixSurface: fixSurface)
        }
        let mustFix = summary["must_fix"] as? Int ?? 0
        let unknown = summary["unknown"] as? Int ?? 0
        return (schemaVersion, rows, mustFix, unknown)
    }

    /// The count-never-score summary line (copy deck §3.12), pluralized
    /// honestly, never a percentage or gauge.
    var verifySummaryLine: String {
        if verifyMustFix == 0 && verifyUnknown == 0 { return "Everything's ready to hand over." }
        let mustFixPart: String
        if verifyMustFix == 0 { mustFixPart = "Nothing must be fixed." }
        else if verifyMustFix == 1 { mustFixPart = "1 thing must be fixed." }
        else { mustFixPart = "\(verifyMustFix) things must be fixed." }
        let unknownPart: String
        if verifyUnknown == 0 { unknownPart = "Nothing couldn't be checked." }
        else if verifyUnknown == 1 { unknownPart = "1 thing couldn't be checked." }
        else { unknownPart = "\(verifyUnknown) things couldn't be checked." }
        return mustFixPart + " " + unknownPart
    }

    func jumpTarget(for fixSurface: String) -> AdminSelection? {
        switch fixSurface {
        case "describe": return .onboarding(.describeOrg)
        case "connect-github": return .onboarding(.connectGitHub)
        case "connect-store": return .governance(.connectStore)
        default: return nil
        }
    }
}

// MARK: - Surface 9: Handed off (the blind resting state, no fake spinner)

extension AdminRootView {
    var handedOffView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Setup is running in your terminal",
            intro: "Claude Code is setting up your organization now."
        ) {
            AdminCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This app can't see your terminal, so it won't guess how it's going. When Claude Code says it's done, run the Setup check and this app will read the result straight from GitHub.")
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        model.advance(from: .handedOff)
                    } label: {
                        Text("Run the Setup check")
                    }
                    .buttonStyle(.borderedProminent)

                    Text("You can close this. Your organization's setup lives on GitHub, and the Setup check reads it fresh every time.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
            }
        } leadingActions: {
            backButton { model.goBack(from: .handedOff) }
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Surface 10: Setup check (real verify shell-out, rendered not
// computed; count-never-score; drift + deferred-store + beyond-plan rows)

extension AdminRootView {
    var setupCheckView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "The setup check",
            intro: "An honest look at what's really on GitHub now. Every red names who has to fix it."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if model.verifyState == .idle {
                    AdminCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Run the setup check before you hand this over. It catches blockers before your organization does.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Run the setup check") {
                                model.runSetupCheck()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .foregroundColor(Color(nsColor: .labelColor))
                    }
                } else {
                    Text("This reads what's really on GitHub, not what you typed here. If setup did more or less than your plan, you'll see it below.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    if model.verifyState == .working {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking what's really on GitHub...")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        }
                    } else if let degraded = model.verifyDegradedLine {
                        AdminCard {
                            Text(degraded)
                                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        AdminCard {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(model.verifyRows.enumerated()), id: \.offset) { index, row in
                                    verifyRowView(row)
                                    if index < model.verifyRows.count - 1 { Divider() }
                                }
                            }
                        }

                        Text(model.verifySummaryLine)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(Color(nsColor: .labelColor))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
        } leadingActions: {
            if model.verifyState != .idle {
                Button("Run it again") { model.runSetupCheck() }
                    .buttonStyle(.bordered)
            }
        } primaryAction: {
            primaryButton(
                "Continue",
                enabled: model.verifyState == .success && model.verifyDegradedLine == nil && model.verifyMustFix == 0
            ) {
                model.advance(from: .setupCheck)
            }
        }
    }

    private func verifyRowView(_ row: VerifyRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            verifyGlyph(row.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.detail)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                if row.status == "present-undeclared" {
                    Text("This wasn't in your plan. Setup added it, and that's fine.")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            Spacer()
            if row.status == "pass" {
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            if !row.owner.isEmpty, row.status == "fail" || row.status == "unknown" || row.status == "deferred" {
                OwnerChip(owner: row.owner)
            }
            if row.status == "fail" || row.status == "deferred", let target = model.jumpTarget(for: row.fixSurface) {
                Button(row.status == "deferred" ? "Connect ›" : "Go fix this") {
                    model.selection = target
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: .controlAccentColor))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.check), \(row.status)\(row.owner.isEmpty ? "" : ", " + row.owner)")
    }

    private func verifyGlyph(_ status: String) -> some View {
        Group {
            switch status {
            case "pass":
                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(nsColor: .systemGreen))
            case "fail":
                Image(systemName: "xmark.circle.fill").foregroundColor(Color(nsColor: .systemRed))
            case "unknown":
                Image(systemName: "questionmark.circle").foregroundColor(Color(nsColor: .systemOrange))
            case "deferred":
                Image(systemName: "circle.dotted").foregroundColor(Color(nsColor: .secondaryLabelColor))
            case "present-undeclared":
                Image(systemName: "circle.fill").foregroundColor(Color(nsColor: .secondaryLabelColor))
            default:
                Image(systemName: "circle").foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Surface 11: Done, and what now

extension AdminRootView {
    var doneView: some View {
        StepShell(
            eyebrow: "ONBOARDING",
            title: "Your organization is set up",
            intro: "The spaces exist, the teams can reach them, and your setup file is in place. Two things to do next."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AdminCard(title: "Invite the team, on GitHub") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(inviteTeamLine)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open your teams ›") {
                            let org = model.orgSlug
                            if let url = URL(string: "https://github.com/orgs/\(org)/teams") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(nsColor: .controlAccentColor))
                    }
                }
                AdminCard(title: "Point users at the app") {
                    Text("Your team installs Copilot Control Tower themselves, and it sets them up from what you just built. Send them the app, and they'll see the departments they're on.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            backButton { model.goBack(from: .done) }
        } primaryAction: {
            EmptyView()
        }
    }

    /// Copy deck §3.13's worked example names "Sales" verbatim; the real
    /// surface substitutes the org's actual first department (QA fix), and
    /// falls back to a neutral phrasing when none exist yet, keeping the
    /// same sentence shape.
    private var inviteTeamLine: String {
        if let first = model.departments.first(where: { !$0.slug.isEmpty }) {
            return "People join a department by being added to its team on GitHub. Add someone to the \(first.name) team and they can join \(first.name) from their own copilot. This app never manages people. GitHub does."
        }
        return "People join a department by being added to its team on GitHub. This app never manages people. GitHub does."
    }
}

// MARK: - Governance Surface 12: Add a department (routes into Describe)

extension AdminRootView {
    var addDepartmentView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Add a department",
            intro: "Add a department here. Setting up again only adds what's new and never touches what's already there."
        ) {
            AdminCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(existingStateLine)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Describe the addition") {
                        model.selection = .onboarding(.describeOrg)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundColor(Color(nsColor: .labelColor))
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }

    private var existingStateLine: String {
        let names = model.departments.filter { !$0.slug.isEmpty }.map { $0.name }
        let deptText = names.isEmpty ? "no departments yet" : names.joined(separator: ", ")
        return "Your organization already has: \(deptText), on \(model.harness.displayName). Add a new department and you'll see the plan for just its three spaces and its team. You can also add the other harness alongside \(model.harness.displayName) for the whole organization; it only adds the new spaces and leaves everything else alone."
    }
}

// MARK: - Governance Surface 13: Someone left (instructional guidance only,
// triggers nothing; CONTRACT SEAM below on the lookup result)

extension AdminRootView {
    var someoneLeftView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Someone left",
            intro: "This app doesn't manage people. When someone leaves, remove them from their teams on GitHub. Then rotate the keys those teams could reach in your shared store, so their old access is worthless."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Who left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    TextField("octocat", text: $model.someoneLeftLookup)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Button("Look up") {
                        model.someoneLeftLookedUp = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.someoneLeftLookup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if model.someoneLeftLookedUp {
                    // CONTRACT SEAM: reading a person's real team membership
                    // and the registry-derived key names they could reach
                    // needs a live, per-person `gh` read this build does not
                    // implement. Render the designed honest holding line
                    // rather than invent team/key rows.
                    AdminCard {
                        Text("I couldn't read the result of this, so I won't guess.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Governance Surface 14: Connect the shared store (deferred case;
// rewrites the SAME canonical brief per admin-standup-contract.md §1.4)

extension AdminRootView {
    var connectStoreGovernanceView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Connect the shared store",
            intro: "Connect the store that holds your organization's shared keys. Your integrations will need it before they can work. A shared secret store hands out keys by GitHub team, so a key never lives in a repo or in this app."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                AdminCard {
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

                        if !model.departments.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Which teams can use it")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                ForEach(model.departments) { dept in
                                    if !dept.slug.isEmpty {
                                        HStack {
                                            Text(dept.name).frame(width: 120, alignment: .leading)
                                            Text("→").foregroundColor(Color(nsColor: .tertiaryLabelColor))
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
                    }
                }

                AdminCard(title: "How this is added") {
                    Text("This adds your store pointer to your organization's setup. It never deletes or overwrites anything already there. Claude Code makes the change in your terminal, the same way it set up your organization.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.governanceStoreCommandReady {
                    AdminCard {
                        CopyableCodeBlock(text: model.handoffCommand, copyLabel: "Copy the command to add it")
                    }
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            primaryButton(
                "Copy the command to add it",
                enabled: model.storeAddressLooksValid && !model.storeAddress.isEmpty
            ) {
                Task {
                    model.storeStatus = .connected
                    await model.writeBriefAndMaterializeSkill()
                    model.governanceStoreCommandReady = model.briefWriteState == .success
                }
            }
        }
    }
}

// MARK: - Governance Surface 15: Org setup (read-only summary)

extension AdminRootView {
    var orgSetupView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Your organization's setup",
            intro: "Everything your organization hands out, in one place. This comes from your organization's setup on GitHub. It isn't editable here, by design."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if model.orgSlug.isEmpty {
                    AdminCard {
                        Text("Describe your organization first, so there's something here to read.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                } else {
                    AdminCard(title: "Copilots & harness") {
                        Text("Harness: \(model.harness.displayName). Codex · Knowledge · CLI.")
                    }
                    AdminCard(title: "Departments") {
                        let names = model.departments.filter { !$0.slug.isEmpty }.map { $0.name }
                        Text(names.isEmpty ? "None yet." : names.joined(separator: " · "))
                    }
                    AdminCard(title: "Published integrations") {
                        // CONTRACT SEAM: no seam reads per-repo registry
                        // manifests yet (admin-standup-contract.md §5); this
                        // always renders the honest empty state rather than
                        // invent published entries.
                        Text("None published yet.")
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    AdminCard(title: "Where your shared keys come from") {
                        if model.storeStatus == .connected {
                            Text(model.storeAddress)
                                .font(.system(.callout, design: .monospaced))
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Not connected yet. Connect one before your first shared integration can work.")
                                Button("Connect the store ›") {
                                    model.selection = .governance(.connectStore)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Color(nsColor: .controlAccentColor))
                            }
                        }
                    }
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Governance Surface 16: Analytics (off by default)

extension AdminRootView {
    var analyticsView: some View {
        StepShell(
            eyebrow: "GOVERNANCE",
            title: "Usage data",
            intro: "Off. Nothing is shared unless you turn this on and your organization signs off on it."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Share anonymous usage data", isOn: $model.analyticsEnabled)
                    .toggleStyle(.switch)

                AdminCard(title: "What this would share") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Which copilots and departments this Mac has set up.")
                        Text("How often this app is opened.")
                        Text("Whether setup finished without errors.")
                    }
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            .font(.body)
            .foregroundColor(Color(nsColor: .labelColor))
        } leadingActions: {
            EmptyView()
        } primaryAction: {
            EmptyView()
        }
    }
}

// MARK: - Admin window controller

/// Owns the Admin window + its `AdminModel` for the app's lifetime, same
/// singleton shape as `WizardWindowController`. `isReleasedWhenClosed =
/// false` so closing the window never deallocates it — reopening picks up
/// wherever Earl left off (nothing is lost by closing mid-progression, since
/// nothing here is locked; interaction-design §1.3).
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
