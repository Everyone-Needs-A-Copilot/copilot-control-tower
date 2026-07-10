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
// This file is the app's entry point (`@main`) plus the tray/popover UI. It is
// compiled together with `native/models.swift` (shared data model) and
// `native/wizard.swift` (the S2 first-run wizard window) into ONE `.app`-less
// binary via `swiftc native/*.swift -o ...` (see
// `scripts/control-tower-tray.command`), the same no-Xcode-project pattern
// `scripts/publisher_setup.swift` uses for its own single-file build.
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

// Data model (BadgeState, Layer, ComponentView, RenderState, DevScenario, ...) and
// the shared `AviatorGlyph`/`ControlTowerGlyph` asset loaders now live in
// `native/models.swift`, compiled together with this file (see
// `scripts/control-tower-tray.command`: `swiftc native/*.swift -o ...`). They moved
// there when `native/wizard.swift` landed so both this tray and the wizard window
// build against one set of type mirrors instead of two drifting copies.

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
        // Owner directive: the aviators glyph is menu-bar-tray-ONLY (see
        // `AviatorGlyph`'s doc comment in `native/models.swift`) — this popover
        // header must never draw it. The obvious swap-in, the full-color
        // `ControlTowerGlyph` illustration, was tried and rejected: rasterized
        // at this header's ~20pt scale its detail collapses into an
        // unreadable colored blob (verified during this change), which is
        // worse than no brand image at all. So this view draws ONLY the
        // status badge mark (`symbolAndColor`) — nothing when the state is
        // `.none`, consistent with the badge vocabulary's own "silence is the
        // success state" rule (see `BadgeState.symbolAndColor`'s doc comment)
        // and this app's "Quiet Instrument" design intent.
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
    /// Opens the first-run wizard window (S2). Provided by `StatusBarController`
    /// so this view stays a pure render of `TrayModel` plus this one navigation
    /// callback, the same "view owns no AppKit state itself" shape the rest of
    /// this file already uses.
    let onOpenWizard: () -> Void

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

    // Region 5 — action row (Set up, Sync now, Settings). "Set up" opens the
    // first-run wizard window (S2) on demand — the interaction spec's second
    // entry point into it, alongside the dev-only tray menu item
    // (`StatusBarController.buildMenu()`). "Sync now" and "Settings" stay mock
    // no-ops in this slice (cli-unreadable renders "Sync now" as its one retry
    // action, per §2.4).
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Set up") {
                onOpenWizard()
            }
            .buttonStyle(.bordered)
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(model: model, onOpenWizard: { [weak self] in self?.openWizard() })
        )
    }

    // MARK: Wizard (S2) — the popover's "Set up" action, the second entry point
    // besides the dev-only menu item below (`buildMenu()`).

    private func openWizard() {
        popover.performClose(nil)
        WizardWindowController.shared.show()
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
        // DEV-ONLY: a second, always-available entry point to the wizard (S2),
        // alongside the popover's "Set up" action — lets the owner open it on
        // demand for review without waiting for a setup-needed scenario.
        let openWizardItem = NSMenuItem(title: "Open Wizard (dev)", action: #selector(openWizardMenuAction), keyEquivalent: "")
        openWizardItem.target = self
        menu.addItem(openWizardItem)

        // Admin mode (S4, `native/admin.swift`) — ADM-0 entry. Copy deck §1.9
        // gates this row on `admin_capable`; this build ratifies the flow
        // doc's open decision 6 as "always-available" (path 2b: every
        // unmanaged user is their own admin), per this task's own ratified
        // default, so the item is unconditional here rather than reading a
        // gating fact. Revisit if the owner later ratifies path 2a instead.
        let openAdminItem = NSMenuItem(title: "Open Administration...", action: #selector(openAdminMenuAction), keyEquivalent: "")
        openAdminItem.target = self
        menu.addItem(openAdminItem)

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

    @objc private func openWizardMenuAction() {
        openWizard()
    }

    // MARK: Admin (S4) — the Admin face's ADM-0 entry point.

    @objc private func openAdminMenuAction() {
        popover.performClose(nil)
        AdminWindowController.shared.show()
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

        // DEV/SMOKE-TEST ONLY: opens the wizard window immediately at launch when
        // `CT_OPEN_WIZARD=1` is set, so a headless smoke test can prove the wizard
        // view itself doesn't crash without needing a live click. Env-gated so a
        // normal launch is completely unaffected (no window, accessory-only, same
        // as before this existed).
        if ProcessInfo.processInfo.environment["CT_OPEN_WIZARD"] == "1" {
            WizardWindowController.shared.show()
        }

        // DEV/SMOKE-TEST ONLY: mirrors `CT_OPEN_WIZARD` above, but for the
        // Admin face (`native/admin.swift`) — opens Administration immediately
        // at launch when `CT_OPEN_ADMIN=1` is set, so a headless smoke test
        // can prove the Admin path doesn't crash without a live click.
        if ProcessInfo.processInfo.environment["CT_OPEN_ADMIN"] == "1" {
            AdminWindowController.shared.show()
        }
    }
}

// `@main`, not a top-level `ControlTowerTrayApp.main()` call: this app is now
// compiled as three files together (`swiftc native/*.swift`, see
// `scripts/control-tower-tray.command`), and Swift only permits top-level
// executable statements in a lone file named `main.swift` in a multi-file,
// non-single-file compilation — `@main` is the portable entry-point spelling
// that works whether this file is compiled alone or alongside
// `models.swift`/`wizard.swift`.
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
