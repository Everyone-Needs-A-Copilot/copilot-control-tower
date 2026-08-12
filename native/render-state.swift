//
// Copilot Control Tower — pure DoctorReport -> RenderState derivation.
//
// This file is the ONLY place that turns a real `CliClient` result
// (`native/cli-client.swift`/`native/cli-dtos.swift`) into the render-layer
// shapes `native/models.swift` defines (`RenderState`/`HeaderView`/
// `ComponentView`/`LayerView`/`BadgeState`). It is deliberately pure: every
// function here is `static`, takes DTOs in, and returns render structs out —
// no I/O, no `CliClient` calls, no singletons. `native/control-tower-tray.swift`/
// `native/wizard.swift` own calling `CliClient` and feeding this file's
// results into `TrayModel`; this file owns none of that wiring (kept out of
// scope for this phase — see the compat rule in `models.swift`'s header).
//
// PARSE, NEVER COMPUTE (SOUL Principle 2): every glyph and sentence below is
// a closed translation FROM a CLI-computed field. The current doctor schema
// does not carry per-component or per-layer display verdicts, so this file
// deliberately leaves `components` empty instead of aggregating checker
// severities into a second app-owned verdict.

import Foundation

// MARK: - DoctorStatus -> BadgeState (closed map)

extension DoctorStatus {
    /// The tray/popover glyph for this status. A DELIBERATELY COARSER mapping
    /// than `control-tower-copy-deck.md`'s full 12-badge table (that table
    /// gives `updating-app` its own `spinner` and `update-available` its own
    /// `update` badge) — this phase's frozen plan collapses
    /// `syncing`/`updatingApp`/`updateAvailable` onto a single `.ring`, and
    /// `needsAttention`/`itConfigIncomplete` onto a single `.triangle`. Revisit
    /// against the fuller copy-deck table in a later phase if the owner wants
    /// the richer glyph set; this phase implements the frozen mapping verbatim.
    var badge: BadgeState {
        switch self {
        case .healthy: return .none
        case .setupNeeded: return .hollow
        case .signedOut: return .key
        case .syncing, .updatingApp, .updateAvailable: return .ring
        case .needsAttention, .itConfigIncomplete: return .triangle
        case .offline, .waitingForNetwork: return .cloudSlash
        }
    }
}

// MARK: - Product -> display name (copy-deck.md §"Copilot", never "product")

private func displayName(forProduct product: String) -> String {
    switch product {
    case "claude": return "Claude Copilot"
    case "codex": return "Codex Copilot"
    case "cli": return "CLI Copilot"
    case "knowledge": return "Knowledge Copilot"
    default: return "\(product.capitalized) Copilot"
    }
}

/// `control-tower-copy-deck.md` §1.1's plain-language layer names ("To Bob,
/// prefer 'your organization', 'your department', 'this Mac', 'your team'").
private func plainLayer(_ layer: String?) -> String {
    switch layer {
    case "foundation": return "core setup"
    case "org": return "organization"
    case "dept", "department": return "department"
    case "personal": return "personal setup"
    default: return "setup"
    }
}

// MARK: - RenderState derivation

extension RenderState {
    /// The real (non-mock) path: turns a decoded `DoctorReport` plus an
    /// optional `LayersReport` (for the "Join available" Region 3 row) into
    /// the exact `RenderState` shape the tray/popover already renders.
    /// `joinable` is `nil` when `copilot layers --json` was not called or
    /// itself failed — a failed/omitted layers call never blocks rendering
    /// the doctor verdict; Region 3 is simply empty in that case, same as it
    /// already is for a user with no entitled-but-unjoined layers at all.
    static func from(_ doctor: DoctorReport, joinable: LayersReport?) -> RenderState {
        let joinableEntries = (joinable?.layers ?? []).filter { $0.entitled == true && !$0.joined }
        let header = HeaderView(
            glyphState: doctor.status.badge,
            sentence: sentence(for: doctor, joinableCount: joinableEntries.count)
        )
        return RenderState(
            clientState: .ok,
            cliUnreadableReason: nil,
            host: doctor.host,
            status: CliStatus(rawValue: doctor.status.rawValue),
            offline: doctor.offline,
            header: header,
            components: []
        )
    }

    /// The CLI-unreadable ("bang") path: any `CliError` from `native/cli-client.swift`
    /// collapses to the existing `.bang` glyph plus the honest "I won't guess"
    /// copy — never a fabricated status, per `control-tower-copy-deck.md` §1.2.
    static func unreadable(_ error: CliError) -> RenderState {
        RenderState(
            clientState: .cliUnreadable,
            cliUnreadableReason: unreadableReason(for: error),
            host: nil,
            status: nil,
            offline: false,
            header: HeaderView(
                glyphState: .bang,
                sentence: "I can't read the setup right now, so I won't guess."
            ),
            components: []
        )
    }

    private static func unreadableReason(for error: CliError) -> CliUnreadableReason {
        switch error {
        case .notFound, .launchFailed: return .ioError
        case .exit2: return .exit2
        case .parse: return .parseError
        case .schemaOutOfRange: return .schemaOutOfRange
        case .missingSecurityField: return .missingSecurityField
        }
    }

    // MARK: Sentence (closed map, VERBATIM per the frozen plan; the three
    // statuses the plan left unspecified — setup-needed/it-config-incomplete/
    // needs-attention — are filled from the ratified `control-tower-copy-deck.md`
    // §1.1 so this switch stays total over all 10 `DoctorStatus` values.)

    private static func sentence(for doctor: DoctorReport, joinableCount: Int) -> String {
        switch doctor.status {
        case .healthy:
            return joinableCount > 0
                ? "Everything on this Mac is set up."
                : "Everything is set up."
        case .syncing, .updatingApp:
            return "Bringing everything up to date…"
        case .updateAvailable:
            return "An update is ready."
        case .offline, .waitingForNetwork:
            return "You're offline. I'll pick up where I left off when you're back."
        case .signedOut:
            if let component = signedOutComponent(doctor) {
                return "\(component) needs you to sign in. Everything else is fine."
            }
            return "You need to sign in. Everything else is fine."
        case .setupNeeded:
            return "Let's finish setting you up."
        case .itConfigIncomplete:
            let names = incompleteComponentNames(doctor)
            if names.count > 1 {
                return "Some copilots are waiting on setup from your organization."
            } else if let name = names.first {
                return "\(name) is waiting on setup from your organization."
            }
            return "Your organization hasn't finished setting this up."
        case .needsAttention:
            if let attention = needsAttentionComponent(doctor) {
                return "\(attention.name) needs attention in your \(attention.layer)."
            }
            return "Something needs attention."
        }
    }

    /// Component name for the signed-out sentence, "from the CLI-flagged
    /// auth[]/checker entry" (the frozen plan's own phrasing): prefers the
    /// first non-passing checker that names a `product`, since that is the
    /// entry the CLI itself tied to this signed-out verdict.
    private static func signedOutComponent(_ doctor: DoctorReport) -> String? {
        guard let checker = doctor.checkers.first(where: { $0.severity != .pass && $0.product != nil }) else {
            return nil
        }
        return checker.product.map(displayName(forProduct:))
    }

    private static func incompleteComponentNames(_ doctor: DoctorReport) -> [String] {
        let products = doctor.checkers
            .filter { $0.severity == .fail && $0.product != nil }
            .compactMap { $0.product }
        return Array(Set(products)).sorted().map(displayName(forProduct:))
    }

    private static func needsAttentionComponent(_ doctor: DoctorReport) -> (name: String, layer: String)? {
        let worst = doctor.checkers.first(where: { $0.severity == .fail })
            ?? doctor.checkers.first(where: { $0.severity == .warn })
        guard let checker = worst else { return nil }
        let name = checker.product.map(displayName(forProduct:)) ?? "Something"
        return (name, plainLayer(checker.layerRole ?? checker.layer))
    }

}

// MARK: - "Recently" / What-changed lines from a fan-out report

/// Renders the popover's "What changed" disclosure from a `FanoutReport`
/// (`copilot update --fanout --json`) — a headline plus one row per
/// (project, component) result. Kept separate from `RenderState` itself
/// (which only ever derives from a `DoctorReport`) since a fan-out result is
/// its own, occasionally-fetched, popover disclosure, not part of the
/// steady-state header/component tree.
enum FanoutRender {
    struct ProjectRow {
        let name: String
        let detail: String
    }

    /// "Updated {component} across {updated} of your projects[, to {sha}]."
    /// The trailing "to {sha}" clause is only included when every updated
    /// project actually landed on the SAME target (`lock_after`) — the
    /// fan-out shape carries no single machine-wide semantic version field
    /// (`update.schema.json`/`projects.schema.json`), so this never
    /// fabricates a shared version number across projects that landed on
    /// different targets.
    static func headline(_ report: FanoutReport, componentName: String = "your components") -> String {
        let targets = Set(report.results.compactMap { $0.report?.lockAfter })
        if targets.count == 1, let target = targets.first {
            return "Updated \(componentName) across \(report.summary.updated) of your projects, to \(target)."
        }
        return "Updated \(componentName) across \(report.summary.updated) of your projects."
    }

    /// One "Recently" row (Arc 4, screen 22): a per-component line, always
    /// with a "See projects" link, since every line this derives is one of
    /// the per-project fanned-out components (Claude/Codex).
    struct ComponentLine {
        let text: String
    }

    /// Per-component "Recently" lines (Arc 4, screen 22: "Updated Claude
    /// Copilot across 12 of your projects to v5.9.0." / a separate "Updated
    /// Codex Copilot across 4 of your projects to v5.9.0." line when both
    /// updated) -- one line per CSE component this fan-out actually touched,
    /// grouped from `report.results` by `component`, replacing `headline`'s
    /// single aggregate line with the walkthrough's real per-component rows.
    ///
    /// AS-7 (the walkthrough's own annotation) splits Claude/Codex as the
    /// per-project fanned-out components versus Knowledge/CLI as
    /// "global-once". This function only ever derives Claude/Codex lines
    /// from `report.results`, because that is the only per-component data
    /// `fanout_report` (`projects.schema.json`) actually carries today --
    /// its shape is `additionalProperties: false` with no global-once field,
    /// unlike `all_projects_freshness.global` (a DIFFERENT verb's JSON,
    /// `copilot freshness --all-projects --json`, which is a read-only
    /// staleness snapshot, not a "this fan-out just updated it" signal). A
    /// future contract revision that adds a global-once field to
    /// `fanout_report` itself would extend this function to emit those lines
    /// too ("the global-once lines when the report carries them"); until
    /// then this never fabricates an "Updated Knowledge Copilot."-style line
    /// from a different verb's freshness read, per invariant #1.
    static func componentLines(_ report: FanoutReport) -> [ComponentLine] {
        [ResultItemComponent.claude, .codex].compactMap { component in
            let items = report.results.filter { $0.component == component }
            let updated = items.filter { $0.report?.result == .applied }
            guard !updated.isEmpty else { return nil }

            let name = displayName(forProduct: component.rawValue)
            let targets = Set(updated.compactMap { $0.report?.lockAfter })
            if targets.count == 1, let target = targets.first {
                return ComponentLine(text: "Updated \(name) across \(updated.count) of your projects, to \(target).")
            }
            return ComponentLine(text: "Updated \(name) across \(updated.count) of your projects.")
        }
    }

    static func rows(_ report: FanoutReport) -> [ProjectRow] {
        report.results.map { item in
            let name = URL(fileURLWithPath: item.path).lastPathComponent

            if let outcome = item.result {
                switch outcome {
                case .upToDate: return ProjectRow(name: name, detail: "Already up to date")
                case .blocked: return ProjectRow(name: name, detail: item.reason ?? "Blocked")
                }
            }

            guard let itemReport = item.report else {
                return ProjectRow(name: name, detail: "No report")
            }
            switch itemReport.result {
            case .applied: return ProjectRow(name: name, detail: "Updated to \(itemReport.lockAfter)")
            case .held: return ProjectRow(name: name, detail: "Waiting on your unsaved changes")
            case .blocked: return ProjectRow(name: name, detail: "Blocked")
            case .offline: return ProjectRow(name: name, detail: "Offline")
            case .upToDate: return ProjectRow(name: name, detail: "Already up to date")
            }
        }
    }
}

// MARK: - Organization connections (task 221 bridge stage C)

/// Pure derivation from an already-decoded `ConnectionsReport`
/// (`native/cli-dtos.swift`) into the "Ready to use" / "Available to
/// connect" two-card layout `native/wizard.swift`'s step 6 and
/// `native/user-settings.swift`'s "Your connections" card BOTH render --
/// shared here (like `native/user-settings.swift`'s `UserSettingsRender` is
/// already reused from `native/control-tower-tray.swift`) so the
/// grouping/wording logic exists exactly once, while each surface keeps its
/// own independent SwiftUI styling for the cards themselves (this app's
/// existing convention: shared DERIVATION, independent VIEWS -- neither
/// surface's `sectionCard`/`settingsCard` helper is shared either).
enum ConnectionsRender {
    /// `secret_state == ready` rows, in the CLI's own `connections[]` order
    /// (never re-sorted).
    static func readyRows(_ report: ConnectionsReport) -> [ConnectionRow] {
        report.connections.filter { $0.secretState == .ready }
    }

    /// `secret_state == needs-connect` rows -- the store is reachable, but at
    /// least one required name is absent from it.
    static func needsConnectRows(_ report: ConnectionsReport) -> [ConnectionRow] {
        report.connections.filter { $0.secretState == .needsConnect }
    }

    /// `no-store` rows, PLUS a genuinely unrecognized future `secret_state`
    /// (`.unknown` -- `cli-dtos.swift`'s lenient-decode note). Fail-closed:
    /// an unrecognized state is never rendered as ready, and grouping it
    /// here (rather than silently dropping the row) means it still gets an
    /// honest `store.detail`-driven explanation.
    static func noStoreRows(_ report: ConnectionsReport) -> [ConnectionRow] {
        report.connections.filter { $0.secretState == .noStore || $0.secretState == .unknown }
    }

    /// Quiet-voice sentence for one `needs-connect` row, e.g. "Needs 2
    /// credentials in your organization's secret store: INFISICAL_CLIENT_ID,
    /// INFISICAL_CLIENT_SECRET." Exactly `missing`'s names, in order --
    /// never a value, never tier/mode jargon.
    static func needsConnectDetail(_ row: ConnectionRow) -> String {
        let count = row.missing.count
        let noun = count == 1 ? "credential" : "credentials"
        return "Needs \(count) \(noun) in your organization's secret store: \(row.missing.joined(separator: ", "))."
    }

    /// The whole-roster explanation for when there is nothing to group into
    /// either card at all (`connections` empty -- per the schema, only when
    /// `result == "copilot-unavailable"`) -- the CLI's own `detail`, never a
    /// raw error or an app-invented sentence.
    static func unavailableDetail(_ report: ConnectionsReport) -> String {
        report.detail ?? "Control Tower could not read your organization's connections right now."
    }

    /// Quiet second line shown alongside the pre-existing static "no
    /// additional connections" sentence, specifically when the `connections`
    /// call itself failed in the one shape a `connections`-unaware `cc`
    /// build produces (`CliError.looksLikeMissingConnectionsVerb` below) --
    /// never shown for any other failure kind.
    static let updateHint = "Update to see your organization's connections."
}

// MARK: - The Connect sheet (task 222)

/// Pure derivation from a decoded `ConnectReport` (or a failed CLI seam) into
/// the one thing the Connect sheet needs to know: what to say, and whether the
/// row is now ready. Shared by `native/wizard.swift`'s step 6 and
/// `native/user-settings.swift`'s "Your connections" card, exactly like
/// `ConnectionsRender` above — shared DERIVATION, independent VIEWS.
///
/// The discipline this type exists to enforce: **every sentence about what the
/// CLI did comes from the CLI** (invariant #1). This app owns copy only for
/// conditions it observed itself — the helper could not be reached, or the
/// helper answered in a shape the contract does not allow — and even then it
/// never invents a REASON, only states what it can honestly stand behind.
enum ConnectRender {
    enum Outcome: Equatable {
        /// The CLI re-checked after writing and the row came back ready. This
        /// is the ONLY state the sheet is allowed to call success, and it is
        /// the CLI's verdict, not the app's inference from "the write didn't
        /// error".
        case connected(ConnectionRow)
        /// The CLI answered, and the answer was not "ready". `title` is
        /// CLI-authored whenever the CLI supplied one; `details` are the
        /// CLI's own per-credential sentences, in the CLI's own order.
        case notConnected(title: String, details: [String])
        /// The app could not get a trustworthy answer at all. App-owned copy,
        /// naming no reason it cannot prove.
        case unreadable(String)
    }

    /// The sheet's own framing when the CLI reported `ok` but the row is still
    /// not ready — a partial per-credential failure, which by design does NOT
    /// change the envelope-level result (`connect.schema.json`'s `credentials`
    /// note). States the observed fact; the reasons underneath it are the
    /// CLI's.
    static let partialTitle = "Not everything was saved."

    /// Used only when the CLI said `ok`, the row is still not ready, and there
    /// is no per-credential detail to show either — a shape the contract
    /// permits but does not explain. Claims nothing about why.
    static let unexplainedTitle = "This connection still isn't ready."

    static func outcome(for report: ConnectReport) -> Outcome {
        // A `check` reply to a `connect` call (or vice versa) is a contract
        // violation. Fail closed rather than reading a row that may describe
        // a different question than the one asked.
        guard report.mode == .connect else {
            return .unreadable("Control Tower couldn't confirm what was saved, so it won't say this is connected.")
        }

        let failures = (report.credentials ?? [])
            .filter { $0.outcome == .failed }
            .compactMap { credential -> String? in
                guard let detail = credential.detail, !detail.isEmpty else { return nil }
                return "\(credential.name): \(detail)"
            }

        if report.result == .ok, let service = report.service, service.secretState == .ready {
            return .connected(service)
        }

        if let detail = report.detail, !detail.isEmpty {
            return .notConnected(title: detail, details: failures)
        }

        return failures.isEmpty
            ? .notConnected(title: unexplainedTitle, details: [])
            : .notConnected(title: partialTitle, details: failures)
    }

    /// The CLI seam itself failed. Deliberately does NOT reuse the raw
    /// `CliError` payload in any form — this app never shows a raw error
    /// (`control-tower-copy-deck.md`'s hard rule) — and deliberately does not
    /// distinguish the causes on screen: from the person's side they are one
    /// state, "nothing was saved and nothing was changed".
    static func outcome(for error: CliError) -> Outcome {
        switch error {
        case .notFound, .launchFailed:
            return .unreadable("The setup helper isn't available on this Mac right now, so nothing was saved.")
        default:
            // An installed helper that predates the `connect` verb produces
            // the SAME structural exit-2-with-no-envelope shape
            // `looksLikeMissingConnectionsVerb` already classifies for the
            // roster read (`connections`). That is not hypothetical: every
            // released build before this one bundles a helper with no
            // `connect` verb at all, so without this branch the first person
            // to press the button they were just promised gets a sentence
            // with no way forward in it. Reuses the existing classifier and
            // the existing hint rather than inventing a second reading of the
            // same failure.
            let hint = error.looksLikeMissingConnectionsVerb
                ? " \(ConnectionsRender.updateHint)"
                : ""
            return .unreadable("Control Tower couldn't save these right now. Nothing was changed.\(hint)")
        }
    }
}

extension CliError {
    /// True for the one `CliError` shape an installed `cc` build with no
    /// `connections` verb at all produces: exit code 2 (Click's own
    /// usage-error exit) with no readable `{schema_version, error}` envelope
    /// -- a missing verb never gets far enough to print one (verified live
    /// against the bundled 0.3.2 app's `cc 2.1.2` helper, task 221 stage C:
    /// empty stdout, "No such command 'connections'." on stderr, exit 2).
    /// This is a STRUCTURAL check on the already-classified `CliError` case,
    /// never a scan of stderr text (this app never reads stderr at all --
    /// `cli-client.swift`'s "never shows a raw error" rule) or the JSON body.
    /// A genuinely different exit-2 failure that also happens to omit its
    /// envelope collapses onto the SAME honest "can't check right now,
    /// update to see more" copy -- never a false negative, and never a
    /// misleading claim either.
    var looksLikeMissingConnectionsVerb: Bool {
        if case .exit2(let code, _) = self { return code == "unknown" }
        return false
    }
}

/// Connections-specific load state, carrying the real `CliError` on failure
/// (unlike `native/user-settings.swift`'s `UserSettingsLoadState<Value>`,
/// whose shared `.failed` case deliberately carries none -- that generic is
/// reused across six unrelated report kinds via `UserSettingsModel.load()`'s
/// `Result.loadedState`, none of which need the specific error; adding a
/// payload there would ripple into all of them for a need only this screen
/// has). Shared by BOTH `WizardModel` and `UserSettingsModel`.
enum ConnectionsLoadState {
    case waiting
    case loading
    case loaded(ConnectionsReport)
    case failed(CliError)
}
