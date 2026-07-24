//
// Copilot Control Tower — native macOS menu-bar app ("Quiet Instrument").
//
// The app's entry point (`@main`) plus the tray/popover UI: an `NSStatusItem`
// + `NSPopover` that renders the component-currency popover against the REAL
// CLI, per:
//   - docs/09-prototypes/user-experience-walkthrough.html, Arc 3 (screens
//     16-20: the quiet tray, opening the popover, Sync now, a department
//     appears) and Arc 4 (screens 21-22: an update lands, the honest "What
//     changed" summary) — copy is VERBATIM from that document, no em-dashes.
//   - docs/03-design/control-tower-copy-deck.md — the closed vocabulary for
//     every string this file renders (§1.1-1.9).
//   - docs/03-design/control-tower-visual-system.md (tokens, materials, the
//     12 shape-first BadgeState glyphs, spacing/type).
//
// This file is compiled together with `native/models.swift` (shared render
// data model), `native/cli-client.swift` + `native/cli-dtos.swift` (the CLI
// seam), `native/render-state.swift` (the pure DoctorReport -> RenderState
// derivation), and `native/wizard.swift` (the S2 first-run wizard window)
// into ONE binary via `swiftc native/*.swift -o ...` (see
// `scripts/build-user.command` / `scripts/build-admin.command`).
//
// PARSE, NEVER COMPUTE (CLAUDE.md invariant #1): this file calls `CliClient`
// verbs and renders `RenderState`/`FanoutRender` output. It computes NOTHING
// about ecosystem health itself — every glyph, sentence, and dot below is a
// render of an already-CLI-computed verdict.
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory`): no
// blocking `Process`/file I/O may run during a SwiftUI `@State`/
// `@StateObject` property-wrapper `init()` — it re-enters the AttributeGraph
// mid-update and aborts. `TrayModel.init()` below is pure (only assigns
// `@Published` defaults, no I/O, no CLI calls). Every CLI call in this file
// happens from `TrayModel.refresh()`/`syncNow()`/`join(_:)` — async methods
// invoked from `applicationDidFinishLaunching(_:)` or later (via `Task`), a
// button action, or a timer callback, never from a property-wrapper `init()`.
// `StatusBarController.init()`'s one piece of synchronous file I/O — loading
// the aviator SVG for the tray glyph — is safe for the same reason the prior
// revision of this file documented: AppKit calls it from
// `applicationDidFinishLaunching(_:)`, entirely outside SwiftUI's own
// view/attribute graph.

import AppKit
import Foundation
import ServiceManagement
import SwiftUI

// Data model (BadgeState, Layer, ComponentView, RenderState, ...) lives in
// `native/models.swift`; the CLI seam lives in `native/cli-client.swift` +
// `native/cli-dtos.swift`; the DoctorReport -> RenderState derivation (plus
// `FanoutRender`, the "What changed" line-rendering helpers) lives in
// `native/render-state.swift`. All three are compiled together with this
// file — see this file's header.

// MARK: - Join-row state (Region 3, per-department join lifecycle)

/// One `CliClient.layersJoin(id:)` attempt's UI state, per
/// `control-tower-copy-deck.md` §1.5. `idle` is the default "Join" row;
/// `joining` is the in-flight quiet spinner (no ETA); `message` covers every
/// terminal non-`joined` outcome (`not-entitled`/`offline`/`error`/a `CliError`
/// itself), `canRetry` controlling whether the row keeps its `Join` button.
enum JoinRowState: Equatable {
    case idle
    case joining
    case message(String, canRetry: Bool)
}

// MARK: - View model

/// The single source of truth for the tray/popover: owns every real
/// `CliClient` call this app makes outside the wizard/admin faces. A
/// `@MainActor` class (not a plain `actor`) because its `@Published`
/// properties drive SwiftUI directly; every one of its async methods still
/// only ever calls `CliClient` (itself off-main internally — see
/// `native/cli-client.swift`), so nothing here blocks the main thread.
/// `init()` is pure — no I/O, no CLI calls — safe to construct from
/// `StatusBarController.init()` (itself invoked from
/// `applicationDidFinishLaunching(_:)`, see this file's header).
@MainActor
final class TrayModel: ObservableObject {
    /// The honest "haven't asked yet" placeholder shown for the brief instant
    /// between app launch and the first `refresh()` completing. Never shown
    /// as `.ok`/healthy (that would fabricate a verdict this app hasn't
    /// actually observed yet) — a quiet, bare-glyph, non-claiming line.
    private static let notYetChecked = RenderState(
        clientState: .ok,
        cliUnreadableReason: nil,
        host: nil,
        status: nil,
        offline: false,
        header: HeaderView(glyphState: .none, sentence: "Checking your setup…"),
        components: []
    )

    @Published private(set) var state: RenderState = TrayModel.notYetChecked
    /// Region 3, "Available to join": entitled-but-not-joined department/org
    /// rows, derived from `layers()` the same way `render-state.swift`'s
    /// `RenderState.from(_:joinable:)` derives its own (private) joinable
    /// count — that filter is duplicated here (rather than exposed from
    /// `render-state.swift`, which is out of this file's ownership this
    /// task) because Region 3 needs the actual `LayerEntry` rows, not just a
    /// count.
    @Published private(set) var joinable: [LayerEntry] = []
    @Published var joinRowStates: [String: JoinRowState] = [:]
    @Published private(set) var authStatus: AuthStatus?
    @Published private(set) var isSyncing = false
    /// Populated ONLY by `syncNow()` (`update --fanout --json`) — the "What
    /// changed" drill-in's data source (Region 4's "Recently" disclosure and
    /// Region 6's held-project prompt both read this).
    @Published private(set) var lastFanout: FanoutReport?
    /// Populated by `refresh()` (`freshness --all-projects --json`) — the
    /// other half of the "does 'What changed' have anything to show" gate
    /// (Region 5), for the case where the app just launched and has no
    /// in-memory `lastFanout` yet but a prior sync's results are still
    /// visible in the per-project sweep.
    @Published private(set) var lastFreshness: AllProjectsFreshness?
    /// Bounded Git-workspace activation state computed by `cc`. Ready
    /// workspaces stay invisible; only a missing/unfinished shared setup can
    /// enter the Bob lane below.
    @Published private(set) var lastWorkspaces: WorkspacesReport?
    @Published private(set) var isConfiguringWorkspace = false
    @Published private(set) var workspaceBlocker: WorkspaceEntry?

    /// Concurrently calls `doctor()` + `layers()` (steady-state verdict +
    /// Region 3's join candidates) and `authStatus()` + `freshnessAllProjects()`
    /// (Region 4's GitHub row, Region 5's "What changed" gate). A failed
    /// `layers()`/`authStatus()`/`freshnessAllProjects()` call never blocks
    /// rendering the `doctor()` verdict — same "a secondary call's failure
    /// degrades gracefully" rule `render-state.swift`'s own doc comment
    /// states for `joinable`.
    func refresh() async {
        async let doctorResult = CliClient.shared.doctor()
        async let layersResult = CliClient.shared.layers()
        async let authResult = CliClient.shared.authStatus()
        async let freshnessResult = CliClient.shared.freshnessAllProjects()
        async let workspacesResult = CliClient.shared.workspaces()

        let doctor = await doctorResult
        let layers = await layersResult
        let auth = await authResult
        let freshness = await freshnessResult
        let workspaces = await workspacesResult

        switch doctor {
        case .success(let report):
            let joinableReport: LayersReport?
            if case .success(let report2) = layers {
                joinableReport = report2
            } else {
                joinableReport = nil
            }
            state = RenderState.from(report, joinable: joinableReport)
            joinable = (joinableReport?.layers ?? []).filter { $0.entitled == true && !$0.joined }
        case .failure(let error):
            state = RenderState.unreadable(error)
            joinable = []
        }

        if case .success(let status) = auth {
            authStatus = status
        } else {
            authStatus = nil
        }

        if case .success(let report) = freshness {
            lastFreshness = report
        }
        // A failed sweep keeps whatever `lastFreshness` this app already had
        // — a stale-but-present sweep is still useful for the "What changed"
        // gate; a failure is never treated as "nothing happened".

        if case .success(let report) = workspaces {
            lastWorkspaces = report
            // A portable project identity lets the CLI associate the user's
            // private profile locally. This is reversible machine state, not
            // a shared-repository write, so ready workspaces need no prompt.
            for workspace in report.workspaces where
                workspace.state == .ready && workspace.personalProfile.state == .available {
                _ = await CliClient.shared.configureWorkspace(
                    path: workspace.path,
                    components: workspace.recommendedComponents,
                    shareWithProject: false,
                    apply: true
                )
            }
        }
    }

    var workspaceNeedingSetup: WorkspaceEntry? {
        workspaceBlocker ?? lastWorkspaces?.workspaces.first {
            $0.state == .setupAvailable || $0.state == .activationRequired
        }
    }

    func configureWorkspace(_ workspace: WorkspaceEntry) async {
        guard !isConfiguringWorkspace else { return }
        isConfiguringWorkspace = true
        defer { isConfiguringWorkspace = false }
        let shouldShare = workspace.declaredComponents.isEmpty
        if case .success(let report) = await CliClient.shared.configureWorkspace(
            path: workspace.path,
            components: workspace.recommendedComponents,
            shareWithProject: shouldShare,
            apply: true
        ) {
            lastWorkspaces = report
            if let blocked = report.workspaces.first(where: { $0.state == .blocked }) {
                workspaceBlocker = blocked
                return
            }
            workspaceBlocker = nil
        }
        await refresh()
    }

    /// Region 5's "Sync now": the one manual escape hatch in steady state.
    /// Runs `update()` (apply pending changes) then `update --fanout` (the
    /// per-project roll-up "What changed" reads), then re-derives the header
    /// via a normal `refresh()`. Guarded against re-entry and against firing
    /// while offline (§1.7: "disabled while offline").
    func syncNow() async {
        guard !isSyncing, !state.offline else { return }
        isSyncing = true
        defer { isSyncing = false }

        _ = await CliClient.shared.update()
        if case .success(let report) = await CliClient.shared.updateFanout() {
            lastFanout = report
        }
        await refresh()
    }

    /// Region 3's `Join` action (`control-tower-copy-deck.md` §1.5). On a
    /// successful join (`joined`/`already-joined`) the row is cleared locally
    /// and a full `refresh()` runs so the component tree picks up the newly
    /// entitled layer's passing dots — "the tree filling in is the reward",
    /// never a toast. Every other outcome renders its own verbatim §1.5
    /// message, `canRetry` controlling whether `Join` reappears.
    func join(_ entry: LayerEntry) async {
        guard joinRowStates[entry.id] != .joining else { return }
        joinRowStates[entry.id] = .joining

        switch await CliClient.shared.layersJoin(id: entry.id) {
        case .success(let result):
            switch result.result {
            case .joined, .alreadyJoined:
                joinRowStates[entry.id] = nil
                await refresh()
            case .notEntitled:
                joinRowStates[entry.id] = .message("\(entry.name) isn't available to you anymore.", canRetry: false)
            case .offline:
                joinRowStates[entry.id] = .message("Waiting for the network.", canRetry: true)
            case .error:
                joinRowStates[entry.id] = .message("Couldn't join \(entry.name) right now. Try again.", canRetry: true)
            }
        case .failure:
            joinRowStates[entry.id] = .message("Couldn't join \(entry.name) right now. Try again.", canRetry: true)
        }
    }
}

// MARK: - Popover material (real NSVisualEffectView vibrancy, never a flat fill)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Region 1: status header glyph

struct GlyphView: View {
    let badgeState: BadgeState

    var body: some View {
        // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
        // `AviatorGlyph`'s doc comment in `native/models.swift`) — this popover
        // header never draws it. This view draws ONLY the status badge mark
        // (`symbolAndColor`) — nothing when the state is `.none`, consistent
        // with "silence is the success state" (never a green-checkmark
        // reward, per `control-tower-copy-deck.md` hard rule 6).
        ZStack {
            if let mark = badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
            }
        }
        .frame(width: 20, height: 20, alignment: .center)
        .accessibilityHidden(true)
    }
}

// MARK: - Region 2: "YOUR COPILOTS" component tree

/// One layer cell (`control-tower-copy-deck.md` §1.4): a quiet dot when
/// passing (never the colorful `.pass` reward mark — that would be exactly
/// the "green checkmark reward" the copy deck's hard rule 6 forbids), the
/// closed badge-shape vocabulary for warn/fail, and an honest hollow "You're
/// not in this one" mark for a layer the CLI reported no checker for at all
/// (a fixed four-column grid, so a genuinely absent layer still gets its own
/// slot rather than silently collapsing the row).
private struct LayerDot: View {
    let layer: Layer
    let layerView: LayerView?

    private static let plainLabels: [Layer: String] = [
        .foundation: "Core setup",
        .org: "Your organization",
        .dept: "Your department",
        .personal: "This Mac",
    ]

    private var label: String { Self.plainLabels[layer] ?? layer.label }

    var body: some View {
        Group {
            if let layerView, layerView.severity != .pass, let mark = layerView.badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
            } else if layerView != nil {
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(Color(nsColor: .quaternaryLabelColor))
            }
        }
        .frame(width: 16, height: 16)
        .help(tooltip)
        .accessibilityLabel("\(label), \(accessibilityDetail)")
    }

    private var tooltip: String {
        guard let layerView else { return "\(label): You're not in this one" }
        if let detail = layerView.detail, !detail.isEmpty { return "\(label): \(detail)" }
        return label
    }

    private var accessibilityDetail: String {
        guard let layerView else { return "You're not in this one" }
        return layerView.detail ?? layerView.severity.rawValue
    }
}

private struct ComponentTreeRow: View {
    let component: ComponentView

    var body: some View {
        HStack(spacing: 6) {
            Text(component.component)
                .font(.body)
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer(minLength: 8)
            ForEach(Layer.allCases) { layer in
                LayerDot(layer: layer, layerView: component.layers.first(where: { $0.layer == layer }))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.component), \(component.worstSeverity.rawValue)")
    }
}

// MARK: - Region 3: "AVAILABLE TO JOIN"

private struct JoinRow: View {
    let entry: LayerEntry
    let state: JoinRowState
    /// Non-nil disables `Join` and supplies the VoiceOver/tooltip reason
    /// (`control-tower-copy-deck.md` §1.5: "Disabled while offline or
    /// syncing").
    let disabledReason: String?
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            rowContent
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rowContent: some View {
        switch state {
        case .idle:
            Text(entry.name)
                .foregroundColor(Color(nsColor: .labelColor))
            Spacer()
            Button("Join", action: onJoin)
                .buttonStyle(.bordered)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "")
        case .joining:
            Text("Joining \(entry.name)…")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Spacer()
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .message(let text, let canRetry):
            Text(text)
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Spacer()
            if canRetry {
                Button("Join", action: onJoin)
                    .buttonStyle(.bordered)
                    .disabled(disabledReason != nil)
                    .help(disabledReason ?? "")
            }
        }
    }
}

// MARK: - Popover content (six regions, always in this order)

struct PopoverContentView: View {
    @ObservedObject var model: TrayModel
    @State private var showingWhatChanged = false
    @State private var showingProjectDrillIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRegion

            if showingWhatChanged {
                Divider()
                whatChangedRegion
            } else if model.state.clientState != .cliUnreadable {
                // Per `control-tower-copy-deck.md` §1.2, the bang state shows
                // "no tree, no join row" — only the header sentence plus the
                // Region 5 retry action.
                if !model.state.components.isEmpty {
                    Divider()
                    componentTreeRegion
                }
                if !model.joinable.isEmpty {
                    Divider()
                    joinRegion
                }
                Divider()
                integrationsRegion
            }

            Divider()
            actionRow

            bobLaneRegion
        }
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBackground())
    }

    // MARK: Region 1 — status header. `HeaderView.sentence` verbatim, except
    // while a sync is in flight, when the header swaps to the syncing
    // sentence (`control-tower-copy-deck.md` §1.1's `syncing` row).

    private var headerSentence: String {
        model.isSyncing ? "Bringing everything up to date…" : model.state.header.sentence
    }

    private var headerGlyph: BadgeState {
        model.isSyncing ? .ring : model.state.header.glyphState
    }

    private var headerRegion: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(badgeState: headerGlyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerSentence)
                    .font(.headline)
                    .foregroundColor(Color(nsColor: .labelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                if let host = model.state.host {
                    Text(host)
                        .font(.subheadline)
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 2 — "YOUR COPILOTS": one row per CSE component, four
    // fixed layer cells each (`control-tower-copy-deck.md` §1.3/§1.4).

    private var componentTreeRegion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR COPILOTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            ForEach(model.state.components) { component in
                ComponentTreeRow(component: component)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 3 — "AVAILABLE TO JOIN": present only when a joinable
    // entry exists (§1.3), never a badge, never an alarm.

    private var joinDisabledReason: String? {
        if model.state.offline { return "Waiting for the network." }
        if model.isSyncing { return "Finishing an update first." }
        return nil
    }

    private var joinRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVAILABLE TO JOIN")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            ForEach(model.joinable) { entry in
                JoinRow(
                    entry: entry,
                    state: model.joinRowStates[entry.id] ?? .idle,
                    disabledReason: joinDisabledReason,
                    onJoin: { Task { await model.join(entry) } }
                )
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 4 — shared + personal integrations (§1.3/§1.6). No CLI
    // verb backs a shared-integrations list yet (NB-3, not yet built), so
    // that half honestly shows its header/subtitle with no fabricated rows;
    // "YOUR ACCOUNTS" renders the one real integration this app already has
    // data for — GitHub, from `authStatus()`.

    private var githubAccountStatusText: String {
        guard let authStatus = model.authStatus else { return "Needs sign-in" }
        switch authStatus.state {
        case .authorized: return "Signed in"
        case .signedOut: return "Needs sign-in"
        }
    }

    private var integrationsRegion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SHARED WITH YOUR TEAM")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text("Ready for you. Nothing to sign into.")
                .font(.caption2)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))

            Text("YOUR ACCOUNTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .padding(.top, 6)
            HStack {
                Text("GitHub")
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
                Text(githubAccountStatusText)
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 5 — the action row (Sync now / What changed / Settings...).
    // Every button says exactly what it does; never an "Update" button
    // (updates install themselves), per §1.7's hard rule.

    private var showWhatChangedButton: Bool {
        model.lastFanout != nil || !(model.lastFreshness?.projects.isEmpty ?? true)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Sync now") {
                    Task { await model.syncNow() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isSyncing || model.state.offline)

                if showWhatChangedButton {
                    Button("What changed") {
                        showingWhatChanged = true
                        showingProjectDrillIn = false
                    }
                    .buttonStyle(.borderless)
                }

                // `control-tower-copy-deck.md` §1.7: `Set up` appears
                // "when state is setup-needed" and "opens the first-run
                // wizard" — the one path back into the wizard once first
                // run is behind you but the CLI still reports setup as
                // incomplete (e.g. the wizard was closed mid-way via
                // "Continue in the menu bar" from a Holding screen).
                if model.state.status == .setupNeeded {
                    Button("Set up") {
                        WizardWindowController.shared.show()
                    }
                    .buttonStyle(.borderless)
                }

                Button("Settings…") {
                    // Inert placeholder: Settings (S3) is not built this phase.
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)
            }
            if model.state.offline {
                Text("Waiting for the network.")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Region 6 — the Bob lane. Empty in Healthy; the ONE prompt this
    // file renders is the dirty-WIP hold (`control-tower-copy-deck.md` §1.8),
    // exactly one affordance, never a discard button (never-destroy).

    private var bobLaneRegion: some View {
        Group {
            if model.state.clientState != .cliUnreadable,
               let fanout = model.lastFanout, fanout.summary.held > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("You have unsaved changes in the way of an update. Nothing was touched.")
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button("Review your changes") {
                        showingWhatChanged = true
                        showingProjectDrillIn = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
            } else if model.state.clientState != .cliUnreadable,
                      let workspace = model.workspaceNeedingSetup {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspace.state == .blocked
                         ? workspace.detail
                         : (workspace.state == .setupAvailable
                            ? "Copilot is available for \(workspace.name)."
                            : "Finish Copilot setup for \(workspace.name) on this Mac."))
                        .font(.callout)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Button(workspace.state == .blocked
                           ? "Try again"
                           : (workspace.state == .setupAvailable ? "Set up this project" : "Finish setup")) {
                        Task { await model.configureWorkspace(workspace) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isConfiguringWorkspace)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: "What changed" drill-in (Arc 4, screen 22). `FanoutRender`'s
    // "Recently" headline plus, one level deeper, the per-project list and
    // the pinned reassurance line, verbatim.

    private var whatChangedRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("‹ Back") {
                showingWhatChanged = false
                showingProjectDrillIn = false
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: .secondaryLabelColor))

            Text("Recently")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))

            if let fanout = model.lastFanout {
                if showingProjectDrillIn {
                    projectDrillIn(fanout)
                } else {
                    let componentLines = FanoutRender.componentLines(fanout)
                    if componentLines.isEmpty {
                        // Fallback for a fan-out result this run couldn't
                        // break out by component (e.g. nothing applied to
                        // claude/codex specifically) -- the single aggregate
                        // line, same as before this per-component derivation
                        // existed.
                        HStack(alignment: .top) {
                            Text(FanoutRender.headline(fanout))
                                .font(.body)
                                .foregroundColor(Color(nsColor: .labelColor))
                            Spacer()
                            Button("See projects ›") {
                                showingProjectDrillIn = true
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: .linkColor))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(componentLines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top) {
                                    Text(line.text)
                                        .font(.body)
                                        .foregroundColor(Color(nsColor: .labelColor))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button("See projects ›") {
                                        showingProjectDrillIn = true
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(Color(nsColor: .linkColor))
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Nothing has changed since you last looked.")
                    .font(.body)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 12)
    }

    private func projectDrillIn(_ fanout: FanoutReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects brought up to date")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
            Text("Only your copilots' shared files were updated. Your own work in these projects wasn't touched.")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(FanoutRender.rows(fanout).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.name)
                            .font(.callout)
                            .foregroundColor(Color(nsColor: .labelColor))
                        Spacer()
                        Text(row.detail)
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }
            }
        }
    }
}

// MARK: - Status bar controller (NSStatusItem + NSPopover + right-click menu)

@MainActor
final class StatusBarController: NSObject {
    /// Default background refresh cadence for steady state, per this task's
    /// own spec ("every 300 seconds (default)").
    private static let pollInterval: TimeInterval = 300

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    let model = TrayModel()
    private var badgeView: NSImageView?
    private var pollTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        refreshGlyph()
        startPolling()
        performRefresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = AviatorGlyph.load(targetHeight: 16)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityRole(.button)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverContentView(model: model))
    }

    // MARK: Refresh (initial launch, popover open, and the poll timer)

    private func performRefresh() {
        Task { @MainActor in
            await self.model.refresh()
            self.refreshGlyph()
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performRefresh()
            }
        }
    }

    // MARK: Badge overlay (section 4 shape composited bottom-trailing on the
    // template glyph; `.none` draws nothing — the bare glyph is silence).

    private func refreshGlyph() {
        applyBadge(model.state.header.glyphState)
        statusItem.button?.setAccessibilityLabel(model.state.header.sentence)
    }

    private func applyBadge(_ badgeState: BadgeState) {
        badgeView?.removeFromSuperview()
        badgeView = nil
        guard let button = statusItem.button, let mark = badgeState.symbolAndColor else { return }

        let size: CGFloat = 9
        let frame = NSRect(x: max(0, button.bounds.width - size - 1), y: 1, width: size, height: size)
        let imageView = NSImageView(frame: frame)
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let image = NSImage(systemSymbolName: mark.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image = image
        imageView.contentTintColor = mark.color
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isEditable = false
        button.addSubview(imageView)
        badgeView = imageView
    }

    // MARK: Click handling — left-click toggles the popover (and triggers a
    // refresh so it never shows stale data on open), right-click shows the
    // minimal `NSMenu`.

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            togglePopover()
            return
        }
        showMenu()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            performRefresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so the next left-click still toggles the popover instead of
        // reopening this menu (the standard both-gestures-on-one-item trick).
        statusItem.menu = nil
    }

    // MARK: The right-click menu — minimal and production-honest: Sync now,
    // What changed, Settings..., (Admin, gated), Quit. No dev-only "Preview
    // state" section (that fixture-switcher is superseded — real fixtures
    // now come via `CT_CLI_PATH=<path to mock-cc>`).

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let syncItem = NSMenuItem(title: "Sync now", action: #selector(syncNowMenuAction), keyEquivalent: "")
        syncItem.target = self
        syncItem.isEnabled = !model.isSyncing && !model.state.offline
        menu.addItem(syncItem)

        let whatChangedItem = NSMenuItem(title: "What changed", action: #selector(openWhatChangedMenuAction), keyEquivalent: "")
        whatChangedItem.target = self
        menu.addItem(whatChangedItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        #if CT_ADMIN_BUILD
        // Admin mode (S4, `native/admin.swift`/`native/admin-support.swift`) —
        // ADM-0 entry. Compiled only in the Admin build
        // (`scripts/build-admin.command`, `-D CT_ADMIN_BUILD`); the plain
        // user build (`scripts/build-user.command`) never links
        // `AdminWindowController` at all, so this whole block must never
        // appear outside this guard.
        menu.addItem(.separator())
        let openAdminItem = NSMenuItem(title: "Open Administration...", action: #selector(openAdminMenuAction), keyEquivalent: "")
        openAdminItem.target = self
        menu.addItem(openAdminItem)
        #endif

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func syncNowMenuAction() {
        Task { @MainActor in
            await self.model.syncNow()
            self.refreshGlyph()
        }
    }

    @objc private func openWhatChangedMenuAction() {
        guard let button = statusItem.button else { return }
        // The right-click menu itself has no "drill-in" state of its own
        // (that lives in `PopoverContentView`'s local `@State`); this just
        // opens the popover, where "What changed" is one tap away, same as
        // any other steady-state visit.
        performRefresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func showSettingsMenuAction() {
        // Inert placeholder: Settings (S3) is not built this phase.
    }

    #if CT_ADMIN_BUILD
    @objc private func openAdminMenuAction() {
        popover.performClose(nil)
        AdminWindowController.shared.show()
    }
    #endif
}

// MARK: - App entry point (accessory, no Dock icon, no default window)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let firstRunDefaultsKey = "ct.hasCompletedFirstRun"

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment

        #if CT_ADMIN_BUILD
        // The Admin distribution is a conventional double-clickable app, not
        // the User tray with a hidden Administration menu item. Keep the old
        // SELFTEST route for deterministic launch regression coverage.
        if env["CT_SELFTEST"] != "1" {
            NSApp.setActivationPolicy(.regular)

            if env["CT_ADMIN_HARNESS_SELFTEST"] == "1" {
                let model = AdminModel()
                model.orgNameInput = "acme-co"
                model.githubOAuthClientIDInput = "Iv1.a1b2c3d4e5f6a7b8"
                let yaml = model.buildBriefContents()
                let json = model.buildBriefJSONContents() ?? ""
                let yamlHasBoth = yaml.contains("  - claude\n")
                    && yaml.contains("  - codex\n")
                let jsonHarnesses: [String]
                if let data = json.data(using: .utf8),
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let harnesses = payload["harness"] as? [String] {
                    jsonHarnesses = harnesses
                } else {
                    jsonHarnesses = []
                }
                let selected = model.orderedHarnesses.map(\.rawValue)
                model.setHarness(.codex, selected: false)
                let singleYaml = model.buildBriefContents()
                let singleSelectionPass = model.orderedHarnesses.map(\.rawValue) == ["claude"]
                    && singleYaml.contains("  - claude\n")
                    && !singleYaml.contains("  - codex\n")
                    && !model.planCardLines.contains("acme-co/codex-copilot-internal")
                model.setHarness(.claude, selected: false)
                let emptySelectionPass = !model.selectedHarnessesAreValid
                print(
                    "ADMIN_HARNESSES selected=\(selected.joined(separator: ",")) "
                        + "yaml=\(yamlHasBoth ? "pass" : "fail") "
                        + "json=\(jsonHarnesses == selected ? "pass" : "fail") "
                        + "single=\(singleSelectionPass ? "pass" : "fail") "
                        + "empty=\(emptySelectionPass ? "pass" : "fail")"
                )
                exit(
                    selected == ["claude", "codex"]
                        && yamlHasBoth
                        && jsonHarnesses == selected
                        && singleSelectionPass
                        && emptySelectionPass
                        ? 0 : 1
                )
            }

            if env["CT_ADMIN_READINESS_SELFTEST"] == "1" {
                let model = AdminModel()
                model.orgNameInput = env["CT_ADMIN_ORG"] ?? "acme-co"
                Task { @MainActor in
                    await model.runGitHubReadinessCheck()
                    let rows = ReadinessRow.Kind.allCases.map {
                        "\($0.rawValue)=\(String(describing: model.readinessRows[$0].status))"
                    }.joined(separator: ",")
                    print("ADMIN_READINESS \(rows)")
                    exit(model.githubReadinessComplete ? 0 : 1)
                }
                return
            }

            AdminWindowController.shared.show()
            return
        }
        #endif

        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController()
        statusBarController = controller

        let isFirstRun = !LocalDefaults.bool(forKey: Self.firstRunDefaultsKey)
        let forceWizard = env["CT_OPEN_WIZARD"] == "1"

        // AS-6: on first open the wizard auto-presents; opening the app is
        // starting setup. `CT_OPEN_WIZARD=1` forces it open regardless (a
        // dev/smoke-test override, same convention this file has always
        // used), so a headless smoke test can prove the wizard view itself
        // doesn't crash without needing a live click or a clean-slate
        // `LocalDefaults` state (see that type's own doc comment in
        // `native/models.swift` on why this isn't `UserDefaults`/cfprefsd).
        if forceWizard || isFirstRun {
            WizardWindowController.shared.show()
        }

        if isFirstRun {
            // Best-effort login-item registration, once, first-run only.
            // Failure (e.g. this ad-hoc `swiftc`-built binary isn't a signed
            // `.app` bundle SMAppService recognizes, or the user declines) is
            // non-fatal and silent — this app must never surface a login-item
            // error to Bob.
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        }

        #if CT_ADMIN_BUILD
        // DEV/SMOKE-TEST ONLY: opens Administration immediately at launch
        // when `CT_OPEN_ADMIN=1` is set, so a headless smoke test can prove
        // the Admin path doesn't crash without a live click. Admin-build-only
        // — the plain user build never links `AdminWindowController`.
        if env["CT_OPEN_ADMIN"] == "1" {
            AdminWindowController.shared.show()
        }
        #endif

        // SELFTEST HOOK (harness contract): prints one deterministic line of
        // machine-parseable state after the first real `refresh()` completes,
        // then exits. Never runs alongside a forced wizard open (that would
        // race the wizard's own construction against this printing/exiting).
        if env["CT_SELFTEST"] == "1" && !forceWizard {
            Task { @MainActor in
                await controller.model.refresh()
                let badgeToken = Self.selftestBadgeToken(controller.model.state.header.glyphState)
                print("SELFTEST badge=\(badgeToken) sentence=\(controller.model.state.header.sentence)")

                if let fixtureName = env["CT_FIXTURE"], !fixtureName.isEmpty {
                    // Only a genuine projects fixture (e.g. "12-of-14-updated")
                    // decodes as a `FanoutReport` here; a doctor-only fixture
                    // name fails this call and this line is simply omitted,
                    // exactly as this task's own gate example expects.
                    if case .success(let report) = await CliClient.shared.updateFanout() {
                        print("SELFTEST recently=\(FanoutRender.headline(report))")
                    }
                }

                print("SELFTEST firstRun=\(isFirstRun)")
                exit(0)
            }
        }
    }

    /// `SELFTEST badge=` must print one of the seven tokens named in this
    /// task's harness contract, not `BadgeState`'s raw value (e.g. `.cloudSlash`'s
    /// raw value is the hyphenated `"cloud-slash"`, not `"cloudSlash"`).
    private static func selftestBadgeToken(_ badge: BadgeState) -> String {
        switch badge {
        case .none: return "none"
        case .hollow: return "hollow"
        case .key: return "key"
        case .ring: return "ring"
        case .triangle: return "triangle"
        case .cloudSlash: return "cloudSlash"
        case .bang: return "bang"
        default: return badge.rawValue
        }
    }
}

// `@main`, not a top-level `ControlTowerTrayApp.main()` call: this app is
// compiled as multiple files together (`swiftc native/*.swift`), and Swift
// only permits top-level executable statements in a lone file named
// `main.swift` in a multi-file, non-single-file compilation — `@main` is the
// portable entry-point spelling that works either way.
@main
struct ControlTowerTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A window-less scene: `Settings` never auto-shows a window at
        // launch, so combined with `.accessory` above, this app presents as
        // pure `NSStatusItem` menu-bar presence only.
        Settings {
            EmptyView()
        }
    }
}
