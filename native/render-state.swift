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
// PARSE, NEVER COMPUTE (CLAUDE.md invariant #1): every glyph/sentence/severity
// decision below is a closed, total mapping FROM a CLI-computed field, never
// a re-derivation of health from raw facts. In particular, `ComponentView.worstSeverity`
// is the MAX of already-CLI-assigned `Checker.severity` values within a
// product — that is aggregation of an existing verdict, not a new verdict.

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
            components: components(from: doctor.checkers)
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
            return "An update is ready. I'll install it quietly."
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
        return (name, plainLayer(checker.layer))
    }

    // MARK: Component tree (group checkers by product x layer)

    /// Groups `doctor.checkers` by `product`, then by `layer` within each
    /// product, into the existing `ComponentView`/`LayerView` render structs.
    /// A checker with no `product` (e.g. a startup-only network probe) has no
    /// component to belong to and is excluded — it still drove the top-level
    /// `status`/glyph above, it just has no row in Region 2's component tree.
    /// `worstSeverity`/`badgeState` are always the MAX of already-CLI-assigned
    /// `Checker.severity` values, never recomputed from any other field.
    private static func components(from checkers: [Checker]) -> [ComponentView] {
        var order: [String] = []
        var byProduct: [String: [Checker]] = [:]
        for checker in checkers {
            guard let product = checker.product else { continue }
            if byProduct[product] == nil {
                byProduct[product] = []
                order.append(product)
            }
            byProduct[product]?.append(checker)
        }

        return order.map { product in
            let productCheckers = byProduct[product] ?? []
            let layerViews = Layer.allCases.compactMap { layer -> LayerView? in
                let layerCheckers = productCheckers.filter { $0.layer == layer.rawValue }
                guard !layerCheckers.isEmpty else { return nil }
                let worst = worstSeverity(of: layerCheckers)
                let detail = layerCheckers.first(where: { $0.severity == worst })?.detail
                return LayerView(
                    layer: layer,
                    severity: LayerSeverity(rawValue: worst.rawValue) ?? .none,
                    badgeState: displayBadge(worst),
                    detail: detail
                )
            }
            return ComponentView(
                component: displayName(forProduct: product),
                worstSeverity: Severity(rawValue: worstSeverity(of: productCheckers).rawValue) ?? .pass,
                layers: layerViews
            )
        }
    }

    private static func worstSeverity(of checkers: [Checker]) -> CliSeverity {
        if checkers.contains(where: { $0.severity == .fail }) { return .fail }
        if checkers.contains(where: { $0.severity == .warn }) { return .warn }
        return .pass
    }

    private static func displayBadge(_ severity: CliSeverity) -> BadgeState {
        switch severity {
        case .pass: return .pass
        case .warn: return .hollow
        case .fail: return .triangle
        }
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
