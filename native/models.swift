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

    /// Human copy for the component verdict already carried by the render
    /// contract. This maps vocabulary; it does not calculate a verdict.
    var plainLanguageStatus: String {
        switch self {
        case .pass: return "Ready"
        case .warn: return "Needs review"
        case .fail: return "Needs attention"
        }
    }
}

enum LayerSeverity: String {
    case pass, warn, fail, none

    /// Human copy for an already CLI-issued layer verdict. This is a lexical
    /// translation only: it never derives health from repository or checker
    /// facts. Visible strings and VoiceOver share this boundary.
    var plainLanguageStatus: String {
        switch self {
        case .pass: return "Ready"
        case .warn: return "Needs review"
        case .fail: return "Needs attention"
        case .none: return "Not reported"
        }
    }
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

    /// Person-facing name for a layer identifier. Internal identifiers stay
    /// available for strict DTO decoding and identity, but never cross the
    /// visible or accessibility boundary.
    var plainLanguageName: String {
        switch self {
        case .foundation: return "Core setup"
        case .org: return "Your organization"
        case .dept: return "Your department"
        case .personal: return "This Mac"
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

    /// One shared visible/a11y rendering of CLI-provided layer verdicts.
    var plainLanguageLayerSummary: String {
        layers.map {
            "\($0.layer.plainLanguageName): \($0.severity.plainLanguageStatus)"
        }.joined(separator: " · ")
    }

    var plainLanguageAccessibilityLabel: String {
        let status = worstSeverity.plainLanguageStatus
        guard !plainLanguageLayerSummary.isEmpty else {
            return "\(component), \(status)"
        }
        return "\(component), \(status). \(plainLanguageLayerSummary)"
    }
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

// MARK: - Local app persistence (first-run flag)

/// A tiny explicit-`$HOME`-aware persistence helper for this app's own local
/// flags (currently just `ct.hasCompletedFirstRun`, read by
/// `control-tower-tray.swift`'s `AppDelegate` and written by
/// `wizard.swift`'s `WizardModel.finish()`). Deliberately NOT
/// `UserDefaults`/cfprefsd: this binary ships today as a bare,
/// non-`.app`-bundled `swiftc` executable with no `CFBundleIdentifier`, and
/// on this OS cfprefsd resolves EVERY preferences domain (whether reached via
/// `UserDefaults.standard`, an explicit `UserDefaults(suiteName:)`, or the
/// `defaults(1)` CLI) against the real logged-in account's home directory via
/// `getpwuid` — it ignores a process's `$HOME` environment override
/// entirely, and `NSHomeDirectory()` does too. That makes cfprefsd-backed
/// storage fundamentally incompatible with `scripts/tests/smoke-scenarios.sh`'s
/// per-scenario scratch-`HOME` isolation (S1: a truly fresh, empty state;
/// S2: a pre-seeded `ct.hasCompletedFirstRun=true` state) — two different
/// scenarios would otherwise silently collide on the ONE real, persistent,
/// cross-run domain on the machine running the tests.
///
/// `LocalDefaults` instead reads its effective home directory from the raw
/// `HOME` environment variable (which DOES reflect a test harness's scratch
/// override, unlike `NSHomeDirectory()`) and reads/writes a plain property
/// list file directly, bypassing cfprefsd altogether. The file path
/// (`~/Library/Preferences/com.everyoneneedsacopilot.controltower.plist`) is
/// deliberately the SAME path cfprefsd itself would use for that bundle
/// identifier — so once this app ships as a real signed `.app` with that
/// `CFBundleIdentifier` (`src-tauri/tauri.conf.json`'s existing
/// `identifier`), a normal `UserDefaults.standard` read picks up this exact
/// file with no migration needed.
enum LocalDefaults {
    private static let domain = "com.everyoneneedsacopilot.controltower"

    private static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(domain).plist")
    }

    private static func readPlist() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    static func bool(forKey key: String) -> Bool {
        (readPlist()[key] as? Bool) ?? false
    }

    static func set(_ value: Bool, forKey key: String) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var plist = readPlist()
        plist[key] = value
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: url)
    }
}

// MARK: - Local admin-standup signal (Holding H6-vs-H7, `native/wizard.swift`)

/// Whether Admin mode's own standup already wrote its non-secret brief on
/// THIS Mac (`AdminPaths.briefPath`/`briefJSONPath`, `native/admin.swift`,
/// Admin-only) — the one zero-network, machine-local signal that tells "a
/// genuine end user" apart from "the person who provisioned this very Mac as
/// the org's admin." No CLI verb carries an org-role token (none could: at
/// the moment Holding's H6 fires there is no credential yet for one to ride
/// on), so this is the only honest discriminator available (invariant #1:
/// still parsing, never computing — reading back a file this Mac's own
/// earlier admin action already wrote is not resolution/sync/compute logic).
///
/// `native/wizard.swift` (compiled into BOTH the User and Admin builds, per
/// `scripts/build-user.command`/`scripts/build-admin.command`'s own source
/// lists) reads this on its own rather than referencing `AdminPaths`, which
/// is Admin-only and unavailable to the User build.
///
/// Reads the path the SAME way `LocalDefaults` above reads its plist (env
/// `HOME`, never `NSHomeDirectory()`, which empirically ignores a process's
/// `$HOME` override even though it does resolve the real logged-in user's
/// home when unset) so `scripts/tests/smoke-scenarios.sh`'s per-scenario
/// scratch-`HOME` isolation can fake presence/absence deterministically; in
/// production `HOME` always matches the real home directory, so this names
/// the exact same file `AdminPaths.briefPath`/`briefJSONPath` do.
enum LocalAdminSignal {
    private static var supportDirectory: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/CopilotControlTower", isDirectory: true)
    }

    /// Mirrors `AdminPaths.briefPath` exactly (`standup-brief.md`).
    static var standupBriefExists: Bool {
        FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent("standup-brief.md").path)
    }

    /// Best-effort read of one field from the non-secret machine-readable
    /// twin (`AdminPaths.briefJSONPath`, `standup-brief.json`): the org's
    /// GitHub App client id, which the admin typed in with their own hands
    /// during standup (`AdminModel.githubOAuthClientIDInput`) and which is
    /// not a secret — GitHub publishes a Client ID, only the App's client
    /// SECRET is sensitive, and that never reaches this file. `nil` on any
    /// read/parse failure or a missing/blank field — never a fabricated
    /// placeholder, so the caller can fall back to the ordinary H6 rather
    /// than assert a fix that isn't actually known.
    static var standupGitHubAppClientID: String? {
        let path = supportDirectory.appendingPathComponent("standup-brief.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let githubApp = payload["github_app"] as? [String: Any],
              let clientID = githubApp["client_id"] as? String
        else { return nil }
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Best-effort read of the brief's top-level `org` field (org-question
    /// copy spec §5/Appendix E.3) — the organization name this Mac's own
    /// admin typed by hand during standup, read the exact same way
    /// `standupGitHubAppClientID` above reads `github_app.client_id`: `nil`
    /// on any read/parse failure or a missing/blank field, never a
    /// fabricated placeholder. The one signal `org-required`'s silent
    /// standup-brief retry (`WizardModel.handleOrgRequired`) is allowed to
    /// act on without ever showing a screen.
    static var standupOrgName: String? {
        let path = supportDirectory.appendingPathComponent("standup-brief.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let org = payload["org"] as? String
        else { return nil }
        let trimmed = org.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
/// SF Symbol or any other substitute.
///
/// Resolves the packaged `aviator-glyph.svg` from `Bundle.main` first, then
/// the canonical repo assets for an unbundled development binary. Returns a
/// **template** `NSImage` (every
/// non-transparent pixel becomes a tintable mask, regardless of the `#2D294E`
/// fill baked into the SVG) sized to `targetHeight`, so the tray glyph's own
/// caller tints it via `contentTintColor`/`.foregroundColor` (`.labelColor`).
/// There is deliberately no substitute-symbol fallback: a missing asset may
/// never silently replace the product's settled menu-bar identity. Packaging
/// tests require the resource in every `.app`.
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
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "aviator-glyph", withExtension: "svg") {
            candidates.append(bundled)
        }

        // Unbundled development/selftest binaries run from the repository.
        let cwd = FileManager.default.currentDirectoryPath
        let primary = URL(fileURLWithPath: "assets/brand/aviator-glyph.svg", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
        let legacyFallback = URL(fileURLWithPath: "src-tauri/icons/aviators.svg", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
        candidates.append(contentsOf: [primary, legacyFallback])

        for url in candidates {
            if let svg = NSImage(contentsOfFile: url.path), svg.size.width > 0, svg.size.height > 0 {
                let aspect = svg.size.width / svg.size.height
                svg.size = NSSize(width: targetHeight * aspect, height: targetHeight)
                svg.isTemplate = true
                return svg
            }
        }

        // A blank image is safer than showing the wrong identity. Production
        // packaging fails before distribution if the bundled SVG is absent.
        let missing = NSImage(size: NSSize(width: targetHeight * 1.6, height: targetHeight))
        missing.isTemplate = true
        return missing
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
        // Phase F: canonical brand assets moved to assets/brand/ (see
        // AviatorGlyph.loadFresh's matching comment above). The old
        // docs/10-reference/control-tower.svg path is kept as a fallback for
        // the same mid-migration/unexpected-cwd reason.
        let cwd = FileManager.default.currentDirectoryPath
        let primary = URL(fileURLWithPath: "assets/brand/control-tower-logo.svg", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
        let legacyFallback = URL(fileURLWithPath: "docs/10-reference/control-tower.svg", relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL

        for url in [primary, legacyFallback] {
            if let svg = NSImage(contentsOfFile: url.path), svg.size.width > 0, svg.size.height > 0 {
                let aspect = svg.size.width / svg.size.height
                svg.size = NSSize(width: targetHeight * aspect, height: targetHeight)
                svg.isTemplate = false
                return svg
            }
        }

        // Genuine last-resort fallback: neither SVG could be resolved at all.
        let fallback = NSImage(
            systemSymbolName: "building.2",
            accessibilityDescription: "Copilot Control Tower"
        ) ?? NSImage()
        fallback.isTemplate = false
        return fallback
    }
}
