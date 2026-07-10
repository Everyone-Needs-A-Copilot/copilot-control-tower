//
// Copilot Control Tower — shared native data model.
//
// Split out of `native/control-tower-tray.swift` when the first-run wizard
// (`native/wizard.swift`) landed, so both the tray popover and the wizard window
// compile against ONE set of type mirrors instead of two drifting copies. Compiled
// together with the other `native/*.swift` files into a single binary (see
// `scripts/control-tower-tray.command`): `swiftc native/*.swift -o ...`.
//
// Mirrors (still) `src/types.ts`:
//   - RenderState / ComponentView / LayerView / BadgeState / HeaderView (the
//     popover's steady-state contract; `ProductView.product` renamed
//     `ComponentView.component` per decision D2).
//   - `AviatorGlyph` / `ControlTowerGlyph` are NOT a src/types.ts
//     mirror — they are this native app's own shared asset-loading helpers (see
//     their doc comments). Per owner directive: the aviators glyph is
//     menu-bar-tray-ONLY (`AviatorGlyph`); every other brand-image surface in
//     the app (wizard welcome hero; the wizard roadmap sidebar's eyebrow icon
//     when legible) uses the Control Tower illustration (`ControlTowerGlyph`,
//     `docs/10-reference/control-tower.svg` — the same asset already mirrored as
//     the app icon at `src-tauri/icons/icon.png`).
//
// CRITICAL SwiftUI/AppKit ordering constraint (see `.claude/memory`): no blocking
// `Process`/file I/O may run during a SwiftUI `@State`/`@StateObject` property-
// wrapper `init()`. Nothing in this file runs at `init()` time — `AviatorGlyph.load`
// and `ControlTowerGlyph.load` are lazy, cached, on-demand file reads invoked from
// view `body`/AppKit lifecycle callbacks only (the same safe pattern
// `StatusBarController.init()` already uses, and `PublisherSetupModel.loadBrandIcon()`
// in `scripts/publisher_setup.swift` already establishes for a plain
// computed-view-property SVG load).

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
    /// disclosure row's own trailing worst-wins mark (`ComponentView` carries
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
/// decision D2 (`docs/10-reference/cse-alignment-decisions.md`): the popover and
/// wizard render CSE components (Knowledge / CLI / Claude / Codex Copilot)
/// across entitled layers, never a product catalog.
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
/// rendered by the wizard's own mock data, see `native/wizard.swift`, and are
/// out of scope for the popover's first slice).
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
/// Region 3's "Join available" row and the wizard's Departments step) is not
/// yet a frozen contract verb (native-experience-architecture.md §6, open
/// decision 3) — `src/types.ts` has no DTO for it today, so this struct is
/// this prototype's own stand-in shape, not a mirror of a real contract type.
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

// MARK: - Shared brand asset loading (tray glyph vs. everywhere else)

/// Loads the real Control Tower "aviators" glyph. Per owner directive this is
/// the **menu-bar tray icon's glyph only** — no other surface in the app draws
/// it. (An earlier revision of this doc comment claimed the popover header and
/// wizard welcome hero also rendered the aviators; that was the owner-corrected
/// mistake this change fixes. Those surfaces now use `ControlTowerGlyph` below,
/// or draw no brand image at all where the illustration is illegible at their
/// size — see `ControlTowerGlyph`'s own doc comment and the call sites in
/// `control-tower-tray.swift`/`wizard.swift`.) Never the generic `eyeglasses`
/// SF Symbol as anything but a genuine last-resort fallback.
///
/// Resolves `src-tauri/icons/aviators.svg` repo-relative to the working
/// directory (the launcher `cd`s to the repo root before exec, same convention
/// `PublisherSetupModel.loadBrandIcon()` uses for `docs/10-reference/control-tower.svg`
/// in `scripts/publisher_setup.swift`). Returns a **template** `NSImage` (every
/// non-transparent pixel becomes a tintable mask, regardless of the `#2D294E`
/// fill baked into the SVG) sized to `targetHeight`, so the tray glyph's own
/// caller tints it via `contentTintColor`/`.foregroundColor` (`.labelColor`).
/// Falls back to the `eyeglasses` SF Symbol ONLY if the asset genuinely can't be
/// resolved on disk (e.g. launched from an unexpected working directory) — a
/// real last resort, not the default path.
///
/// Results are cached in-memory per requested height: this can be called from a
/// SwiftUI view `body` (re-evaluated often) without re-reading the file from
/// disk on every render. Never called from a `@State`/`@StateObject` `init()` —
/// see this file's header.
enum AviatorGlyph {
    private static var cache: [Int: NSImage] = [:]

    static func load(targetHeight: CGFloat = 16) -> NSImage {
        let key = Int((targetHeight * 4).rounded())
        if let cached = cache[key] {
            return cached
        }
        let image = loadFresh(targetHeight: targetHeight)
        cache[key] = image
        return image
    }

    private static func loadFresh(targetHeight: CGFloat) -> NSImage {
        let relativePath = "src-tauri/icons/aviators.svg"
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

        if let svg = NSImage(contentsOfFile: url.path), svg.size.width > 0, svg.size.height > 0 {
            let aspect = svg.size.width / svg.size.height
            svg.size = NSSize(width: targetHeight * aspect, height: targetHeight)
            svg.isTemplate = true
            return svg
        }

        // Genuine last-resort fallback: the SVG could not be resolved at all.
        let fallback = NSImage(
            systemSymbolName: "eyeglasses",
            accessibilityDescription: "Copilot Control Tower"
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}

/// Loads the full-color "control tower" illustration — the brand image every
/// surface in this app EXCEPT the menu-bar tray icon should render (the tray
/// keeps the monochrome aviators glyph, see `AviatorGlyph` above). Same asset
/// already mirrored as the app icon at `src-tauri/icons/icon.png` and loaded by
/// `PublisherSetupModel.loadBrandIcon()` in `scripts/publisher_setup.swift`.
///
/// Resolves `docs/10-reference/control-tower.svg` repo-relative to the working
/// directory, same convention as `AviatorGlyph.loadFresh`. Returns the image
/// **full color, non-template** (`isTemplate = false`) sized to `targetHeight`
/// — this illustration is multi-color by design and is never tinted. At small
/// sizes (roughly menu/sidebar icon scale, ~20pt and below) the illustration's
/// detail collapses into an unreadable blob (verified by rasterizing at 20pt);
/// callers at that scale should prefer drawing no brand image at all rather
/// than call this loader — see `GlyphView` in `control-tower-tray.swift` and
/// `WizardRoadmapSidebar` in `wizard.swift`, both of which intentionally omit
/// a brand image for that reason. Falls back to the `building.2` SF Symbol
/// ONLY if the asset genuinely can't be resolved on disk — a real last resort.
///
/// Results are cached in-memory per requested height, same as `AviatorGlyph`.
/// Never called from a `@State`/`@StateObject` `init()` — see this file's
/// header.
enum ControlTowerGlyph {
    private static var cache: [Int: NSImage] = [:]

    static func load(targetHeight: CGFloat = 64) -> NSImage {
        let key = Int((targetHeight * 4).rounded())
        if let cached = cache[key] {
            return cached
        }
        let image = loadFresh(targetHeight: targetHeight)
        cache[key] = image
        return image
    }

    private static func loadFresh(targetHeight: CGFloat) -> NSImage {
        let relativePath = "docs/10-reference/control-tower.svg"
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

        if let svg = NSImage(contentsOfFile: url.path), svg.size.width > 0, svg.size.height > 0 {
            let aspect = svg.size.width / svg.size.height
            svg.size = NSSize(width: targetHeight * aspect, height: targetHeight)
            svg.isTemplate = false
            return svg
        }

        // Genuine last-resort fallback: the SVG could not be resolved at all.
        let fallback = NSImage(
            systemSymbolName: "building.2",
            accessibilityDescription: "Copilot Control Tower"
        ) ?? NSImage()
        fallback.isTemplate = false
        return fallback
    }
}
