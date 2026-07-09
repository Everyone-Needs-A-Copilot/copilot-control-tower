#!/usr/bin/env swift
//
// Copilot Control Tower — native macOS menu-bar prototype ("Quiet Instrument").
//
// First runnable slice of the native replacement for the Tauri app: an
// `NSStatusItem` + `NSPopover` tray that renders the component-currency
// popover per:
//   - docs/03-design/control-tower-visual-system.md   (tokens, materials, the
//     12 shape-first BadgeState glyphs, spacing/type)
//   - docs/03-design/control-tower-interaction-spec.md (popover regions,
//     the "Join available" row, states)
//   - docs/03-design/control-tower-native-experience-architecture.md
//     (S1 = NSStatusItem + popover; the state inventory)
//   - src/types.ts (RenderState / ProductView / LayerView / BadgeState /
//     HeaderView — mirrored below, `ProductView.product` renamed to
//     `ComponentView.component` per decision D2)
//
// Single-file SwiftUI app compiled to a `.app`-less binary via `swiftc`,
// mirroring `scripts/publisher_setup.swift`'s pattern (see
// `scripts/control-tower-tray.command`).
//
// This is a MOCK-BACKED PROTOTYPE: `copilot doctor`/`copilot layers --json`
// are not shelled out to (the component-currency CLI contract verb is not
// yet frozen — see the native-experience-architecture doc §6, open decision
// 3/4). All data below comes from three fixed `RenderState` fixtures the
// owner can flip between via the right-click menu's dev-only "Preview
// state" section, so the three judged states are: Healthy, Join available
// (entitled-not-synced), and CLI-unreadable ("bang").
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory`): no
// blocking `Process`/file I/O may run during a SwiftUI `@State`/
// `@StateObject` property-wrapper `init()` — it re-enters the AttributeGraph
// mid-update and aborts. `TrayModel.init()` below is pure (mock fixtures
// only, no I/O). The one piece of real file I/O in this file — loading the
// aviators SVG for the tray glyph — runs from `StatusBarController.init()`,
// which AppKit calls from `applicationDidFinishLaunching(_:)`, entirely
// outside SwiftUI's view/attribute graph, so it is safe.

import AppKit
import SwiftUI

// MARK: - Data model (mirrors src/types.ts)

/// The 12-token shape-first badge vocabulary (`src/types.ts` `BadgeState`,
/// `control-tower-visual-system.md` §4). Shape is the primary encoder; color
/// (`symbolAndColor` below) is always a second channel.
enum BadgeState: String, CaseIterable {
    case pass
    case ring
    case key
    case update
    case triangle
    case wrench
    case clock
    case cloudSlash = "cloud-slash"
    case bang
    case spinner
    case hollow
    case none

    /// SF Symbol + system color per the closed §4 badge table. `nil` means
    /// "draw nothing" (the bare/`none` glyph — silence is the success state).
    var symbolAndColor: (symbol: String, color: NSColor)? {
        switch self {
        case .none: return nil
        case .pass: return ("circle.fill", .systemGreen)
        case .hollow: return ("circle", .secondaryLabelColor)
        case .wrench: return ("wrench.adjustable", .secondaryLabelColor)
        case .clock: return ("clock", .secondaryLabelColor)
        case .cloudSlash: return ("cloud.slash", .secondaryLabelColor)
        case .ring: return ("arrow.triangle.2.circlepath", .labelColor)
        case .key: return ("key.fill", .systemBlue)
        case .update: return ("arrow.down.circle", .systemBlue)
        case .triangle: return ("exclamationmark.triangle.fill", .systemOrange)
        case .spinner: return ("square.and.arrow.down", .secondaryLabelColor)
        case .bang: return ("exclamationmark.circle.fill", .systemRed)
        }
    }
}

enum Severity: String {
    case pass, warn, fail

    /// Fixed, non-judgmental presentation mapping from an already CLI-computed
    /// `worst_severity` (invariant #1: the severity itself is never derived
    /// here) to one of the closed 12 badge shapes, for the component
    /// disclosure row's own trailing worst-wins mark (`ProductView` carries
    /// `worst_severity` but no separate row-level `badge_state` field, unlike
    /// `LayerView`, which already carries its own `badge_state` straight from
    /// the contract — see `LayerView` below).
    var displayBadge: BadgeState {
        switch self {
        case .pass: return .pass
        case .warn: return .hollow
        case .fail: return .triangle
        }
    }
}

enum LayerSeverity: String {
    case pass, warn, fail, none
}

/// The four inheritance layers (`src/types.ts` `Layer`), in the fixed
/// foundation -> org -> department -> personal order used everywhere in the
/// design docs.
enum Layer: String, CaseIterable, Identifiable {
    case foundation, org, dept, personal
    var id: String { rawValue }

    /// Lower-case display name, matching the tree ASCII in
    /// `control-tower-visual-system.md` §7.1/§7.2 verbatim.
    var label: String {
        switch self {
        case .foundation: return "foundation"
        case .org: return "org"
        case .dept: return "department"
        case .personal: return "personal"
        }
    }
}

/// Mirrors `src/types.ts` `LayerView` field-for-field.
struct LayerView: Identifiable {
    var id: Layer { layer }
    let layer: Layer
    let severity: LayerSeverity
    let badgeState: BadgeState
    let detail: String?
}

/// Mirrors `src/types.ts` `ProductView`, renamed `product -> component` per
/// decision D2 (`docs/reference/cse-alignment-decisions.md`): the popover
/// renders CSE components (Knowledge / CLI / Claude / Codex Copilot) across
/// entitled layers, never a product catalog.
struct ComponentView: Identifiable {
    var id: String { component }
    let component: String
    let worstSeverity: Severity
    let layers: [LayerView]
}

/// Mirrors `src/types.ts` `HeaderView`.
struct HeaderView {
    /// Same badge vocabulary as the tray glyph — worst state across all
    /// components x layers.
    let glyphState: BadgeState
    /// The one honest status sentence. Never fabricated, never reworded.
    let sentence: String
}

enum ClientState: String {
    case ok
    case cliUnreadable = "cli_unreadable"
}

/// The app-owned 11th reason (`src/types.ts` `CliUnreadableReason`) — never
/// CLI-emitted, chosen only from I/O/schema failure.
enum CliUnreadableReason: String {
    case ioError = "io_error"
    case parseError = "parse_error"
    case schemaOutOfRange = "schema_out_of_range"
    case missingSecurityField = "missing_security_field"
    case exit2 = "exit_2"
    case invalidContent = "invalid_content"
}

/// The 10 CLI-emitted status values (`src/types.ts` `CliStatus`). Carried for
/// fidelity with the contract; this prototype's rendering decisions are
/// driven by `HeaderView`/`ComponentView` directly, same as the real UI would
/// be (`status` is descriptive, not itself branched on for layout).
enum CliStatus: String {
    case setupNeeded = "setup-needed"
    case itConfigIncomplete = "it-config-incomplete"
    case healthy
    case syncing
    case updateAvailable = "update-available"
    case needsAttention = "needs-attention"
    case signedOut = "signed-out"
    case offline
    case waitingForNetwork = "waiting-for-network"
    case updatingApp = "updating-app"
}

/// Mirrors `src/types.ts` `RenderState` (the fields this prototype slice
/// renders; `auth_issues` is omitted — the S12/S5 integration registers are
/// out of scope for this first slice, see the summary in the launcher
/// `.command` header).
struct RenderState {
    let clientState: ClientState
    let cliUnreadableReason: CliUnreadableReason?
    let host: String?
    let status: CliStatus?
    let offline: Bool
    let header: HeaderView
    let components: [ComponentView]
}

/// Mock-only placeholder. `copilot layers --json` (the real source for
/// Region 3's "Join available" row) is not yet a frozen contract verb
/// (native-experience-architecture.md §6, open decision 3) — `src/types.ts`
/// has no DTO for it today, so this struct is this prototype's own stand-in
/// shape, not a mirror of a real contract type.
struct JoinableDepartment: Identifiable {
    let id = UUID()
    let name: String
}

// MARK: - Mock fixtures (the three states the owner judges)

extension RenderState {
    private static var allPassLayers: [LayerView] {
        Layer.allCases.map { LayerView(layer: $0, severity: .pass, badgeState: .pass, detail: nil) }
    }

    private static func component(_ name: String, layers: [LayerView], worst: Severity = .pass) -> ComponentView {
        ComponentView(component: name, worstSeverity: worst, layers: layers)
    }

    /// (a) Current / healthy: every component, every entitled layer at
    /// `pass`. Tray glyph bare, popover shows Regions 1-2 only (§7.1).
    static let healthy = RenderState(
        clientState: .ok,
        cliUnreadableReason: nil,
        host: "This Mac",
        status: .healthy,
        offline: false,
        header: HeaderView(glyphState: .none, sentence: "Everything is set up."),
        components: [
            component("Claude Copilot", layers: allPassLayers),
            component("CLI Copilot", layers: allPassLayers),
            component("Codex Copilot", layers: allPassLayers),
            component("Knowledge Copilot", layers: allPassLayers),
        ]
    )

    /// (b) Join available: a department the user is entitled to but has not
    /// joined. Per §2.4/§7.2 this does NOT badge the tray (glyph stays
    /// `none`, bare) — it is a quiet Region 3 row only, never an alarm.
    static let joinAvailable = RenderState(
        clientState: .ok,
        cliUnreadableReason: nil,
        host: "This Mac",
        status: .healthy,
        offline: false,
        header: HeaderView(glyphState: .none, sentence: "Everything on this Mac is set up."),
        components: [
            component("Claude Copilot", layers: allPassLayers),
            component(
                "CLI Copilot",
                layers: [
                    LayerView(layer: .foundation, severity: .pass, badgeState: .pass, detail: nil),
                    LayerView(layer: .org, severity: .pass, badgeState: .pass, detail: nil),
                    LayerView(layer: .dept, severity: .warn, badgeState: .hollow, detail: "Entitled, not yet joined"),
                    LayerView(layer: .personal, severity: .pass, badgeState: .pass, detail: nil),
                ],
                worst: .warn
            ),
            component("Codex Copilot", layers: allPassLayers),
            component("Knowledge Copilot", layers: allPassLayers),
        ]
    )

    /// (c) CLI-unreadable / "bang": the honest "versions don't match, won't
    /// guess" degrade. Per §2.4 the tree and Join row are both hidden; the
    /// only red in the product.
    static let cliUnreadable = RenderState(
        clientState: .cliUnreadable,
        cliUnreadableReason: .parseError,
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

/// The three judgeable states, switched via the tray's right-click menu
/// (dev-only — see `StatusBarController.buildMenu()`).
enum DevScenario: String, CaseIterable, Identifiable {
    case healthy = "Healthy"
    case joinAvailable = "Join available"
    case cliUnreadable = "CLI unreadable"
    var id: String { rawValue }

    var state: RenderState {
        switch self {
        case .healthy: return .healthy
        case .joinAvailable: return .joinAvailable
        case .cliUnreadable: return .cliUnreadable
        }
    }

    /// Only the Join-available scenario has anything for Region 3 to show.
    var joinableDepartments: [JoinableDepartment] {
        switch self {
        case .joinAvailable: return [JoinableDepartment(name: "Sales")]
        default: return []
        }
    }
}

// MARK: - View model

/// Pure, I/O-free. `init()` only assigns static mock fixtures — safe to use
/// from a SwiftUI `@StateObject`/`@ObservedObject` (see the file-header
/// warning about blocking I/O in `@State` init, which does not apply here).
final class TrayModel: ObservableObject {
    @Published private(set) var scenario: DevScenario = .healthy
    @Published private(set) var state: RenderState = DevScenario.healthy.state
    @Published private(set) var joinable: [JoinableDepartment] = DevScenario.healthy.joinableDepartments

    /// Called only from `StatusBarController` (the dev-only state switcher).
    func select(_ scenario: DevScenario) {
        self.scenario = scenario
        self.state = scenario.state
        self.joinable = scenario.joinableDepartments
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

// MARK: - Popover content (Region 1 header, Region 2 component tree,
// Region 3 Join available, Region 5 action row)

struct GlyphView: View {
    let badgeState: BadgeState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(nsColor: .labelColor))
            if let mark = badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 20, height: 20, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

struct LayerCell: View {
    let layer: LayerView

    var body: some View {
        HStack(spacing: 8) {
            Text(layer.layer.label)
                .font(.subheadline)
                .foregroundColor(Color(nsColor: layer.severity == .none ? .tertiaryLabelColor : .secondaryLabelColor))
            Spacer(minLength: 8)
            if layer.severity == .none {
                Text(layer.detail ?? "Not entitled")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            } else if let mark = layer.badgeState.symbolAndColor {
                Image(systemName: mark.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(nsColor: mark.color))
            }
        }
        .help(layer.detail ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(layer.layer.label), \(layer.detail ?? layer.severity.rawValue)")
    }
}

struct ComponentRow: View {
    let component: ComponentView
    @State private var expanded: Bool

    init(component: ComponentView) {
        self.component = component
        _expanded = State(initialValue: component.worstSeverity != .pass)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(component.layers) { LayerCell(layer: $0) }
            }
            .padding(.leading, 16)
            .padding(.top, 4)
        } label: {
            HStack {
                Text(component.component)
                    .font(.body)
                    .foregroundColor(Color(nsColor: .labelColor))
                Spacer()
                if let mark = component.worstSeverity.displayBadge.symbolAndColor {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(nsColor: mark.color))
                }
            }
        }
        .accessibilityLabel("\(component.component), \(component.worstSeverity.rawValue)")
    }
}

struct PopoverContentView: View {
    @ObservedObject var model: TrayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRegion

            if !model.state.components.isEmpty {
                Divider()
                componentTreeRegion
            }

            if !model.joinable.isEmpty {
                Divider()
                joinRegion
            }

            Divider()
            actionRow
        }
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBackground())
    }

    // Region 1 — status header. Renders `HeaderView.sentence` verbatim.
    private var headerRegion: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(badgeState: model.state.header.glyphState)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.header.sentence)
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

    // Region 2 — "Your components": one disclosure row per CSE component,
    // each showing its four entitled-layer cells as small badge marks.
    private var componentTreeRegion: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("YOUR COMPONENTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 12)
            ForEach(model.state.components) { component in
                ComponentRow(component: component)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        }
    }

    // Region 3 — "Join available": a quiet hollow-ring row per entitled,
    // not-yet-joined department, never a badge, never healthy, never an alarm.
    private var joinRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVAILABLE TO JOIN")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            ForEach(model.joinable) { department in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Text(department.name)
                        .font(.body)
                        .foregroundColor(Color(nsColor: .labelColor))
                    Spacer()
                    Button("Join") {
                        // Mock-only: `copilot layers join <id>` is not a
                        // landed verb yet (open decision 3); nothing real to
                        // call from this prototype.
                    }
                    .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(department.name) department, available to join")
            }
        }
        .padding(.horizontal, 12)
    }

    // Region 5 — action row (Sync now, Settings). Mock no-ops in this slice;
    // both stay live (cli-unreadable renders "Sync now" as its one retry
    // action, per §2.4).
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Sync now") {
                // Mock-only: no `copilot doctor --sync`-style verb wired yet.
            }
            .buttonStyle(.bordered)
            Button("Settings") {
                // Mock-only: Settings scene is not built in this first slice.
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Status bar controller (NSStatusItem + NSPopover + right-click menu)

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model = TrayModel()
    private var badgeView: NSImageView?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        refreshGlyph()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = Self.loadTemplateGlyph()
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

    // MARK: Glyph loading (repo-relative, resolved against the working dir —
    // the launcher `.command` `cd`s to the repo root before exec, same
    // convention `publisher_setup.swift`'s `readAppVersion()`/
    // `loadBrandIcon()` use for `tauri.conf.json` / the brand SVG).

    nonisolated private static func loadTemplateGlyph() -> NSImage {
        let relativePath = "src-tauri/icons/aviators.svg"
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

        if let svg = NSImage(contentsOfFile: url.path), svg.size.width > 0, svg.size.height > 0 {
            let targetHeight: CGFloat = 16
            let aspect = svg.size.width / svg.size.height
            svg.size = NSSize(width: targetHeight * aspect, height: targetHeight)
            svg.isTemplate = true
            return svg
        }

        // Fallback: an SF Symbol keeps the tray alive even if the SVG can't be
        // resolved (e.g. launched from an unexpected working directory).
        let fallback = NSImage(
            systemSymbolName: "eyeglasses",
            accessibilityDescription: "Copilot Control Tower"
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    // MARK: Badge overlay (section 4 shape composited bottom-trailing on the
    // template glyph; `none` draws nothing — the bare glyph is silence).

    private func refreshGlyph() {
        applyBadge(model.state.header.glyphState)
        statusItem.button?.setAccessibilityLabel(model.state.header.sentence)
        statusItem.button?.setAccessibilityValue(model.scenario.rawValue)
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

    // MARK: Click handling — left-click toggles the popover, right-click
    // shows the minimal `NSMenu` (About / Preferences / Quit, per interaction
    // spec §1.6) plus the dev-only state switcher.

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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // DEV-ONLY: lets the owner flip between the three judged states
        // without a real CLI. Not part of the shipped-product minimal menu
        // (interaction spec §1.6) — flag for removal before this graduates
        // past a prototype.
        let devHeader = NSMenuItem(title: "Preview state (dev only)", action: nil, keyEquivalent: "")
        devHeader.isEnabled = false
        menu.addItem(devHeader)
        for scenario in DevScenario.allCases {
            let item = NSMenuItem(title: scenario.rawValue, action: #selector(selectScenario(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scenario
            item.state = (model.scenario == scenario) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Copilot Control Tower", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let prefs = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func selectScenario(_ sender: NSMenuItem) {
        guard let scenario = sender.representedObject as? DevScenario else { return }
        model.select(scenario)
        refreshGlyph()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        // Mock-only: Settings (S3) is not built in this first slice.
    }
}

// MARK: - App entry point (accessory, no Dock icon, no default window)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}

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

// Script-mode top-level file (shebang above): `@main` cannot be used
// alongside top-level statements, so invoke `.main()` explicitly, the same
// convention `scripts/publisher_setup.swift` ends with.
ControlTowerTrayApp.main()
