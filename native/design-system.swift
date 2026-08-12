//
// Copilot Control Tower — the native visual-refresh token/component layer.
//
// ONE new file (task 222, `docs/03-design/native-visual-refresh-spec.md`,
// P1-1): `CTSpace`/`CTRadius`/`CTColor`/`CTType`/`CTMotion` plus the six
// components (`CTCard`, `CTCardTitle`, `CTStatusRow`, `CTCalloutNote`,
// `CTDecisionBlock`, `CTChip`). Nothing else changes — every P1 call site
// substitutes a hand-built literal for a token or component defined here; no
// view is restructured, no model or CLI call is touched (spec §0/§4's own
// framing: "a styling pass, not a rework").
//
// Compiled into BOTH faces — added to the explicit source list in
// `scripts/build-user.command` and `scripts/build-admin.command` (never a
// glob, so an Admin-only file can never sneak into the User build).
//
// Why `NSColor(name:dynamicProvider:)` rather than `@Environment(\.colorScheme)`:
// every appearance-dependent token here (`CTColor.card`/`.well`/`.muted`/
// `.faint`/`.state(_:)`) is a plain `static let`/`static func`, usable from
// anywhere a `Color` is usable (including a `ViewModifier`'s own stored
// properties) without threading an `@Environment` read through every call
// site. A dynamic `NSColor` resolves its provider closure itself, once per
// draw, against whatever `NSAppearance` is current — including the
// `.accessibilityHighContrast*` variants Increase Contrast substitutes in —
// which is the same live-tracking behaviour `.labelColor`/`.separatorColor`
// already have, and the same technique this spec's own measurements were
// taken with (`NSAppearance.performAsCurrentDrawingAppearance`, see the
// spec's "Sources" section).

import AppKit
import SwiftUI

// MARK: - State ramp

/// The five-state vocabulary every status colour in this app is drawn from —
/// shared by `CTColor.state(_:)`, `CTCard`'s `.railed` rail bar, and
/// `CTStatusRow`'s glyph vocabulary. `.neutral` is deliberately NOT a vivid
/// hue (spec §2.3: "Gray dominates by design") — its glyphs and text both
/// resolve to `CTColor.muted`.
enum CTState: Equatable {
    case ready
    case attention
    case blocked
    case actionable
    case neutral
}

// MARK: - CTSpace — an 8pt grid with two half-steps (spec §2.1, retires G-8's 13 ad-hoc values)

enum CTSpace {
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    /// The one non-8pt value, kept deliberately (spec §2.1): 8 crowds a
    /// two-line row, 12 loosens the card.
    static let rowV: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let section: CGFloat = 24
    static let pane: CGFloat = 32
    static let paneTop: CGFloat = 24
    /// Reserved: Welcome/Done hero vertical breathing (not consumed in P1).
    static let hero: CGFloat = 48
}

// MARK: - CTRadius (spec §2.2, retires G-8's stray 6/7/12/999 values)

enum CTRadius {
    /// Every bordered card. Buttons/fields/pickers/steppers are NEVER
    /// restyled with this or any other radius — native rounding stays native
    /// (ratified system §5.3).
    static let card: CGFloat = 10
    /// Inset wells: callouts, code blocks, the Connect sheet's field group.
    static let well: CGFloat = 8
    // Chips/pills use `Capsule()` directly (SwiftUI's own always-round
    // shape) rather than a numeric radius token.
}

// MARK: - CTColor (spec §2.3)

enum CTColor {
    // MARK: Surfaces

    static let page = Color(nsColor: .windowBackgroundColor)

    /// Mirrors the walkthrough's paper→panel delta (`#fff`→`#f7f7f8` light,
    /// `#1c1c1f`→`#252529` dark) by tinting `.labelColor` at a low alpha over
    /// whatever sits behind it — the tint itself IS the compositing, so no
    /// separate "over `page`" step is needed at a call site.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        resolvedRGB(.labelColor, in: appearance)
            .withAlphaComponent(isDark(appearance) ? 0.06 : 0.04)
    })

    /// One step deeper than `.card` — reads recessed (the walkthrough's
    /// `.card.inset`).
    static let well = Color(nsColor: NSColor(name: nil) { appearance in
        resolvedRGB(.labelColor, in: appearance)
            .withAlphaComponent(isDark(appearance) ? 0.095 : 0.065)
    })

    /// The native analogue of the walkthrough's `--line`. **This is the
    /// load-bearing token of the whole refresh** (G-1): a hairline border is
    /// the primary signal that a card is a card.
    static let cardBorder = Color(nsColor: .separatorColor)

    /// Row dividers inside a card. Same value as `cardBorder` — `Divider()`
    /// already resolves here on its own; this token exists so a call site
    /// that draws its own hairline (rather than using `Divider()`) still
    /// reads from the same name.
    static let hairline = Color(nsColor: .separatorColor)

    // MARK: Ink

    /// Names, titles, status sentences — anything primary. 14.94:1 light /
    /// 12.23:1 dark.
    static let ink = Color(nsColor: .labelColor)

    /// Replaces `.secondaryLabelColor` for every sentence a person must read
    /// (G-3): 5.74:1 light / 6.77:1 dark, reproducing the walkthrough's
    /// `--muted` to the byte. Reads Increase Contrast itself (via the
    /// resolving `NSAppearance`'s `accessibilityHighContrast*` variant) and
    /// returns full `.labelColor` when active, so the system setting still
    /// does something instead of being swallowed by a fixed opacity.
    ///
    /// MULTIPLIES `.labelColor`'s own native alpha (≈0.85 on both
    /// appearances) by 0.71, matching SwiftUI's own `Color.opacity(_:)`
    /// semantics for the spec's literal `Color(nsColor: .labelColor)
    /// .opacity(0.71)` — NOT a flat `withAlphaComponent(0.71)` override,
    /// which would compound differently and undershoot the walkthrough's
    /// `#666666` target (verified against a live contrast harness, task 222).
    static let muted = Color(nsColor: NSColor(name: nil) { appearance in
        let resolved = resolvedRGB(.labelColor, in: appearance)
        guard !isIncreasedContrast(appearance) else { return resolved }
        return resolved.withAlphaComponent(resolved.alphaComponent * 0.71)
    })

    /// Retained for **≥13pt supplementary text only** — text that may be
    /// skipped without losing a fact (3.95:1 light / 5.89:1 dark; fails the
    /// floor at smaller sizes, per spec §6).
    static let secondary = Color(nsColor: .secondaryLabelColor)

    /// Actor lines, step numbers, unit suffixes — never the sole carrier of a
    /// fact. 4.95:1 light / 6.07:1 dark; clears the bar the walkthrough's own
    /// `--faint` misses (3.09:1). Same multiplicative-alpha reasoning as
    /// `.muted` above (0.66 against `.labelColor`'s own native alpha).
    static let faint = Color(nsColor: NSColor(name: nil) { appearance in
        let resolved = resolvedRGB(.labelColor, in: appearance)
        return resolved.withAlphaComponent(resolved.alphaComponent * 0.66)
    })

    // `.tertiaryLabelColor` (1.88:1 / 2.26:1) is BANNED for text by this
    // refresh (G-4) and deliberately has no token here — every P1 site that
    // used it substitutes `.faint` or `.muted` instead.

    // MARK: State ramp

    /// One dynamic colour per state, backed by `NSColor(name:dynamicProvider:)`
    /// (spec §2.3): dark appearance keeps the system colour unmodified
    /// (already ≥4.8:1 on `#1E1E1E`); light appearance blends it 35% toward
    /// black, which is what pulls raw `.systemGreen`/`.systemOrange`/
    /// `.systemRed`/`.controlAccentColor` (2.22:1 / 2.31:1 / 3.57:1 / 4.02:1)
    /// up over the 4.5:1 floor. TEXT must always go through this function;
    /// glyphs and fills may keep using the raw system colour directly (shape
    /// carries the state, colour is redundant decoration — WCAG 1.4.11).
    static func state(_ kind: CTState) -> Color {
        if kind == .neutral { return muted }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = resolvedRGB(rawStateNSColor(kind), in: appearance)
            if isDark(appearance) { return base }
            let black = resolvedRGB(.black, in: appearance)
            return base.blended(withFraction: 0.35, of: black) ?? base
        })
    }

    private static func rawStateNSColor(_ kind: CTState) -> NSColor {
        switch kind {
        case .ready: return .systemGreen
        case .attention: return .systemOrange
        case .blocked: return .systemRed
        case .actionable: return .controlAccentColor
        case .neutral: return .labelColor
        }
    }

    // MARK: Appearance-resolution plumbing

    /// Forces `color` into a fixed device-RGB representation AS IT WOULD
    /// DRAW under `appearance`. Dynamic system colours (`.labelColor`,
    /// `.systemGreen`, …) do not answer `.usingColorSpace` meaningfully
    /// outside a matching drawing context, so this establishes one first via
    /// `NSAppearance.performAsCurrentDrawingAppearance` (macOS 11+) before
    /// asking. Falls back to the original colour (rather than trapping) if
    /// the conversion is ever unavailable.
    fileprivate static func resolvedRGB(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    fileprivate static func isDark(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
    }

    fileprivate static func isIncreasedContrast(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        return match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
    }
}

// MARK: - CTType (spec §2.4)

/// Roles as small value bundles (font + tracking + uppercasing + a default
/// colour), applied via the `View.ctText(_:color:)` modifier below. A caller
/// that needs a state-dependent colour (e.g. a status word) passes `color:`
/// to override the role's default — matching this app's existing convention
/// of chaining `.font(...).foregroundColor(...)` explicitly rather than
/// hiding colour inside an opaque compound style.
///
/// Deliberate deviation from the ratified system's "semantic styles only"
/// rule (spec §2.4): five roles below have no macOS semantic style at the
/// size the walkthrough proves is right. Each is annotated with the nearest
/// semantic style so a later `@ScaledMetric(relativeTo:)` pass (P3-1) can add
/// Dynamic Type scaling without touching a single call site.
enum CTType {
    struct Role {
        let font: Font
        var tracking: CGFloat = 0
        var uppercase: Bool = false
        var color: Color
        var lineSpacing: CGFloat = 0
    }

    /// Welcome/Done heroes only. Nearest semantic style: `.largeTitle`.
    static let hero = Role(font: .system(size: 30, weight: .semibold), tracking: -0.6, color: CTColor.ink)
    /// Every wizard/Admin step H1 (G-9). Nearest semantic style: `.title`.
    static let stepTitle = Role(font: .system(size: 26, weight: .semibold), tracking: -0.4, color: CTColor.ink)
    /// The intro paragraph under a step title. Nearest semantic style: `.body`.
    static let lead = Role(font: .system(size: 14), color: CTColor.muted, lineSpacing: 2)
    /// "STEP 6 OF 9", "ONBOARDING" (G-10). Nearest semantic style: `.caption`.
    static let eyebrow = Role(font: .system(size: 11, weight: .semibold), tracking: 0.7, uppercase: true, color: CTColor.state(.actionable))
    /// The label above a card's rows (G-7).
    static let cardTitle = Role(font: .system(size: 10, weight: .semibold), tracking: 0.5, uppercase: true, color: CTColor.muted)
    /// Settings card headings, panel headings.
    static let sectionTitle = Role(font: .system(size: 17, weight: .semibold), color: CTColor.ink)
    /// The name in a status row (G-6). Nearest semantic style: `.callout`.
    static let rowTitle = Role(font: .system(size: 13, weight: .semibold), color: CTColor.ink)
    /// The sentence under a row name (G-3). Nearest semantic style: `.caption`.
    static let rowDetail = Role(font: .system(size: 11), color: CTColor.muted)
    /// "Ready", "Needs attention", "Now", "Next" — pass `color:` for the
    /// state. Nearest semantic style: `.caption`.
    static let status = Role(font: .system(size: 11, weight: .semibold), color: CTColor.muted)
    /// Prose inside cards and callouts.
    static let body = Role(font: .system(size: 13), color: CTColor.muted, lineSpacing: 2)
    /// The strong lead of a callout.
    static let bodyStrong = Role(font: .system(size: 13, weight: .semibold), color: CTColor.ink)
    /// Actor lines, "Next actor:", counters.
    static let caption = Role(font: .system(size: 11), color: CTColor.faint)
    /// NEW markers, badge pills.
    static let chip = Role(font: .system(size: 10, weight: .semibold), tracking: 0.6, color: CTColor.muted)
    /// Paths, repo URLs, commands.
    static let mono = Role(font: .system(size: 11, weight: .regular, design: .monospaced), color: CTColor.muted)
    /// Credential NAMES in the Connect sheet — monospaced so `O`/`0` and
    /// `I`/`l` are distinguishable.
    static let monoLabel = Role(font: .system(size: 10, weight: .semibold, design: .monospaced), tracking: 0.4, color: CTColor.muted)
    /// Device-flow `user_code`, access codes.
    static let code = Role(font: .system(size: 24, weight: .semibold, design: .monospaced), tracking: 2, color: CTColor.ink)
}

extension View {
    /// Applies a `CTType.Role`'s font, tracking, uppercasing, colour, and
    /// line spacing in one call. `color`, when supplied, overrides the
    /// role's own default (e.g. a status word's `CTColor.state(_:)`).
    func ctText(_ role: CTType.Role, color: Color? = nil) -> some View {
        self
            .font(role.font)
            .tracking(role.tracking)
            .textCase(role.uppercase ? .uppercase : nil)
            .foregroundColor(color ?? role.color)
            .lineSpacing(role.lineSpacing)
    }
}

// MARK: - CTMotion (spec §2.5)

/// `easeOut` throughout — every animation in this app is an arrival (a row
/// resolving, a step entering, a state landing), never a departure, so there
/// is no `easeIn`. No spring anywhere: springs imply playfulness, and this
/// product's success state is silence.
enum CTMotion {
    /// Hover/press feedback, chip appearance.
    static let fast = Animation.easeOut(duration: 0.12)
    /// Row state transitions, card content swaps, sheet content changes.
    static let normal = Animation.easeOut(duration: 0.20)
    /// Step-to-step transitions.
    static let slow = Animation.easeOut(duration: 0.30)
    /// The `accessibilityReduceMotion` branch — zero duration; callers pair
    /// this with an opacity-only transition rather than a positional one.
    static let reduced = Animation.easeOut(duration: 0)
}

// MARK: - CTCard (spec §3.1)

/// `.ctCard()` — default: card fill + hairline border, radius 10, padding 16.
/// `.ctCard(.well)` — inset: well fill, NO border, radius 8, padding 16.
/// `.ctCard(.railed(.actionable))` — default + 3pt leading accent bar.
/// `.ctCard(.compact)` — default with padding 12, the popover register.
///
/// Cards have no hover, no press, no focus, no selection — they are
/// containers, not controls (spec §3.1's "States: default only"). A card
/// that becomes tappable stops being a `CTCard` and becomes a `Button`
/// wrapping one.
enum CTCardVariant: Equatable {
    case standard
    case well
    case compact
    case railed(CTState)
}

private struct CTCardModifier: ViewModifier {
    let variant: CTCardVariant

    func body(content: Content) -> some View {
        switch variant {
        case .well:
            content
                .padding(CTSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CTRadius.well, style: .continuous)
                        .fill(CTColor.well)
                )
        case .compact:
            bordered(content: content, padding: CTSpace.md)
        case .standard, .railed:
            bordered(content: content, padding: CTSpace.lg)
                .overlay(alignment: .leading) { railBar }
        }
    }

    private func bordered(content: Content, padding: CGFloat) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CTRadius.card, style: .continuous)
                    .fill(CTColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CTRadius.card, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(CTColor.cardBorder, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var railBar: some View {
        if case .railed(let state) = variant {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CTColor.state(state))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 4)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func ctCard(_ variant: CTCardVariant = .standard) -> some View {
        modifier(CTCardModifier(variant: variant))
    }
}

// MARK: - CTCardTitle (spec §3.2)

/// The uppercase micro-label above a card's rows. Fixes G-7 everywhere,
/// including the tray's literal-caps strings — pass a sentence-case source
/// string (`"Your copilots"`) and let `.textCase(.uppercase)` (inside
/// `.ctText`) do the shouting instead of shipping shouted text to VoiceOver
/// and to any future localization.
struct CTCardTitle: View {
    enum Trailing {
        case status(String, CTState)
        case note(String)
    }

    let title: String
    var trailing: Trailing?

    init(_ title: String, trailing: Trailing? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CTSpace.sm) {
            Text(title)
                .ctText(CTType.cardTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: CTSpace.sm)
            trailingView
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .status(let word, let state):
            Text(word).ctText(CTType.status, color: CTColor.state(state))
        case .note(let text):
            Text(text).ctText(CTType.rowDetail)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - CTStatusRow (spec §3.3)

/// The list row: a fixed 20pt glyph gutter, title/detail/footnote, and a
/// trailing status word or button. Consecutive rows separate with
/// `Divider()` at the call site (never a gap) — that hairline is what makes
/// a card read as a list rather than as loose paragraphs.
///
/// One hard rule carried from the walkthrough floor (rule 04, spec §3.3):
/// `trailing: .button` is legal only when the person reading the row can
/// actually complete the action. A row whose only action belongs to someone
/// else takes `.status` and a `CTCalloutNote` naming that person.
struct CTStatusRow: View {
    enum Glyph {
        case filledDot(CTState)
        case ring
        case check(CTState)
        case bang(CTState)
        case arrow(CTState)
        case none
    }

    enum Trailing {
        case status(String, CTState)
        case button(String, accessibilityLabel: String? = nil, action: () -> Void)
        case none
    }

    let glyph: Glyph
    let title: String
    let detail: String?
    var footnote: String? = nil
    var trailing: Trailing = .none
    /// Overrides the row's combined VoiceOver label (spec §6: "CTStatusRow
    /// takes an optional `accessibilityLabel` override for exactly this" —
    /// preserving an existing per-site label verbatim). When nil, defaults to
    /// "{title}, {status word}, {detail}" for a non-interactive row, or
    /// "{title}, {detail}, {footnote}" for a row whose trailing is a button
    /// (the button itself stays a separate accessible element, never folded
    /// into the row's label — floor rule 07: a shared/read-only row carries
    /// no button and no false affordance either way).
    var accessibilityLabelOverride: String? = nil

    private var isInteractiveTrailing: Bool {
        if case .button = trailing { return true }
        return false
    }

    var body: some View {
        if isInteractiveTrailing {
            HStack(alignment: .top, spacing: CTSpace.md) {
                glyphView.frame(width: 20, alignment: .center).accessibilityHidden(true)
                textBlock
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabelOverride ?? plainTextLabel)
                Spacer(minLength: CTSpace.md)
                trailingView
            }
            .padding(.vertical, CTSpace.rowV)
        } else {
            HStack(alignment: .top, spacing: CTSpace.md) {
                glyphView.frame(width: 20, alignment: .center).accessibilityHidden(true)
                textBlock
                Spacer(minLength: CTSpace.md)
                trailingView
            }
            .padding(.vertical, CTSpace.rowV)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelOverride ?? fullRowLabel)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: CTSpace.hair) {
            Text(title).ctText(CTType.rowTitle)
            if let detail {
                Text(detail).ctText(CTType.rowDetail).fixedSize(horizontal: false, vertical: true)
            }
            if let footnote {
                Text(footnote).ctText(CTType.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .filledDot(let state):
            Circle().fill(dotColor(for: state)).frame(width: 8, height: 8)
        case .ring:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .check(let state):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(rawGlyphColor(state))
        case .bang(let state):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(rawGlyphColor(state))
        case .arrow(let state):
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(rawGlyphColor(state))
        case .none:
            EmptyView()
        }
    }

    /// Glyphs may use the raw vivid system colour (shape carries the state,
    /// colour is redundant decoration — WCAG 1.4.11); `.neutral` is the one
    /// exception, since it was never a vivid hue to begin with.
    private func dotColor(for state: CTState) -> Color {
        state == .neutral ? Color(nsColor: .secondaryLabelColor) : rawGlyphColor(state)
    }

    private func rawGlyphColor(_ state: CTState) -> Color {
        switch state {
        case .ready: return Color(nsColor: .systemGreen)
        case .attention: return Color(nsColor: .systemOrange)
        case .blocked: return Color(nsColor: .systemRed)
        case .actionable: return Color(nsColor: .controlAccentColor)
        case .neutral: return Color(nsColor: .secondaryLabelColor)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .status(let word, let state):
            Text(word).ctText(CTType.status, color: CTColor.state(state))
        case .button(let label, let a11yLabel, let action):
            Button(action: action) { Text(label) }
                .buttonStyle(.bordered)
                .accessibilityLabel(a11yLabel ?? label)
        case .none:
            EmptyView()
        }
    }

    private var plainTextLabel: String {
        [title, detail, footnote].compactMap { $0 }.joined(separator: ", ")
    }

    private var fullRowLabel: String {
        var parts = [title]
        if case .status(let word, _) = trailing { parts.append(word) }
        if let detail { parts.append(detail) }
        if let footnote { parts.append(footnote) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - CTCalloutNote (spec §3.4)

/// Glyph gutter + strong lead + body — the shape the honesty voice lives in.
/// No `CTCalloutNote` ever carries a button: if a next step exists it
/// belongs to the surrounding card's action row, so the callout can never
/// look like a control.
struct CTCalloutNote: View {
    let kind: CTCalloutKind
    let lead: String
    let paragraphs: [String]
    let actor: String?

    init(kind: CTCalloutKind, lead: String, body: [String] = [], actor: String? = nil) {
        self.kind = kind
        self.lead = lead
        self.paragraphs = body
        self.actor = actor
    }

    var body: some View {
        HStack(alignment: .top, spacing: CTSpace.md) {
            glyph
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CTSpace.xs) {
                Text(lead).ctText(CTType.bodyStrong).fixedSize(horizontal: false, vertical: true)
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph).ctText(CTType.body).fixedSize(horizontal: false, vertical: true)
                }
                if let actor {
                    Divider().padding(.top, CTSpace.sm)
                    Text(actor).ctText(CTType.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: .systemGreen))
        case .attention:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: .systemOrange))
        case .blocked:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(Color(nsColor: .systemRed))
        }
    }
}

enum CTCalloutKind {
    case info
    case ready
    case attention
    case blocked
}

// MARK: - CTDecisionBlock (spec §3.5)

/// The two-column fact list: a fixed label column and an explanation,
/// hairline-separated. Collapses to stacked label-over-value at accessibility
/// Dynamic Type sizes, matching the walkthrough's own `@media(max-width:680px)`
/// collapse (spec §3.5). Not consumed by any P1 call site (that is P2-1) but
/// built here now, with the rest of the foundation, per spec §3's "six small
/// views and modifiers, all in `native/design-system.swift`."
struct CTDecisionFact {
    enum Style { case plain, mono }
    let label: String
    let value: String
    var style: Style

    init(_ label: String, _ value: String, style: Style = .plain) {
        self.label = label
        self.value = value
        self.style = style
    }
}

struct CTDecisionBlock: View {
    let facts: [CTDecisionFact]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ facts: [CTDecisionFact]) {
        self.facts = facts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                factRow(fact)
                if index < facts.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder
    private func factRow(_ fact: CTDecisionFact) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: CTSpace.hair) {
                Text(fact.label).ctText(CTType.rowDetail)
                valueText(fact)
            }
            .padding(.vertical, CTSpace.sm)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: CTSpace.md) {
                Text(fact.label)
                    .ctText(CTType.rowDetail)
                    .frame(width: 120, alignment: .leading)
                valueText(fact)
            }
            .padding(.vertical, CTSpace.sm)
        }
    }

    @ViewBuilder
    private func valueText(_ fact: CTDecisionFact) -> some View {
        switch fact.style {
        case .plain:
            Text(fact.value).ctText(CTType.body, color: CTColor.ink).fixedSize(horizontal: false, vertical: true)
        case .mono:
            Text(fact.value).ctText(CTType.mono, color: CTColor.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - CTChip (spec §3.6)

/// The inline marker: `CTType.chip` in a capsule stroked `CTColor.cardBorder`.
/// `.new` (via `CTChip.new(_:)`) strokes and tints with
/// `CTColor.state(.actionable)` instead. Not consumed by any P1 call site
/// (retiring the two hand-built chips is P2-5) but built here now, with the
/// rest of the foundation.
struct CTChip: View {
    let text: String
    var isNew: Bool = false

    var body: some View {
        Text(text)
            .ctText(CTType.chip, color: isNew ? CTColor.state(.actionable) : CTColor.muted)
            .padding(.horizontal, CTSpace.sm)
            .padding(.vertical, CTSpace.xs)
            .background(
                Capsule().strokeBorder(isNew ? CTColor.state(.actionable) : CTColor.cardBorder, lineWidth: 1)
            )
    }

    static func new(_ text: String = "NEW") -> CTChip {
        CTChip(text: text, isNew: true)
    }
}
