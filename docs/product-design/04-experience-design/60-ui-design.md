# UI Design

<!--
FACILITATION GUIDE — UI Designer
==================================
The UI Designer defines the visual language — how the product
LOOKS and FEELS, not how it works.

PREREQUISITE: UX Design must be completed first.

CONVERSATION FLOW:
1. Establish visual direction (mood, aesthetic, references)
2. Define the anti-direction (what this should NOT look like)
3. Define design tokens (colors, typography, spacing)
4. Specify component patterns
5. Collect visual references

QUESTIONS TO ASK:

## Round 1: Visual Direction
- "What should this product FEEL like when you look at it?"
- "What existing products or tools have the right aesthetic?"
- "Should this feel like a professional tool? A dashboard? Something
  more modern? More minimal?"
- "What mood should it convey?"
- "Is this product going to have a brand identity, or does it inherit
  from an existing system?"

## Round 2: Anti-Direction
- "What should this absolutely NOT look like?"
- "What visual cliches in this space do you want to avoid?"
- "Are there specific tools whose look you want to stay away from?"
- "What would make this look generic or forgettable?"

## Round 3: Design Tokens
- "Light mode, dark mode, or both?"
- "Color palette — do you have preferences or should this be derived?"
- "Typography — what kind of type?"
- "Density — spacious and airy, or dense and information-rich?"

## Round 4: Component Patterns
- "What are the key components that define this product's look?"
- "How should lists, cards, and data displays look?"
- "What should loading/processing states look like?"
- "How should the primary interaction surface look?"

## Round 5: References
- "Show me 3-5 products that are close to what you want visually."
- "What about each of them works for you?"
- "What would you change about each?"

SYNTHESIS:
Define the aesthetic with a named direction. Include anti-direction
to prevent drift. Design tokens should be specific enough for
implementation.
-->

> **Status: rebuilt from evidence 2026-08-02. Describes the shipping product at v0.3.2** (notarized arm64 DMG, source commit `e0bf0c3`, vendored helper `cc 2.1.2`). This is a **retrofit**, not a proposal. Every token, color, type role, spacing value, radius and badge mark below was read out of the Swift that actually compiles into `Copilot Control Tower.app` and `Copilot Control Tower Admin.app`, or out of the visual design of record at [`docs/03-design/control-tower-visual-system.md`](../../03-design/control-tower-visual-system.md). Nothing here is invented. Where the shipped code and the design of record disagree, **the code wins and the divergence is recorded** in §9. Genuine unknowns are marked `<!-- TODO -->`.

---

## How to read this document

This document is the visual layer of a three-stage native design record. Stage 1 (structure, information architecture, state inventory) is [`control-tower-native-experience-architecture.md`](../../03-design/control-tower-native-experience-architecture.md); Stage 2 (interaction) is [`control-tower-interaction-spec.md`](../../03-design/control-tower-interaction-spec.md); Stage 3 (color, material, type, iconography, spacing, elevation, motion) is [`control-tower-visual-system.md`](../../03-design/control-tower-visual-system.md). This file is the product-design-package view of that record: it names the direction, names the anti-direction, publishes the tokens as they actually exist in code, and specifies the component patterns and the tray badge vocabulary.

**Audience.** Written first for the owner's future self — any later session must be able to pick the visual system up without re-deriving it from 22,650 lines of Swift, so every claim carries a file reference. Written second for non-technical buyers and evaluators, who need to understand what this thing looks like and why it looks restrained on purpose. Written third for organizations weighing whether to adopt it, who should be able to see from the visual language alone that this is infrastructure that stays out of the way, not another dashboard competing for attention.

**Evidence base.** `native/models.swift` (badge vocabulary, brand asset loaders), `native/control-tower-tray.swift` (menu-bar item, popover, six regions), `native/wizard.swift` (step shell, roadmap sidebar, cards, setup rows), `native/user-settings.swift` (settings window, component and tier rows), `native/admin.swift` + `native/admin-support.swift` (Admin card grammar, run checklist, chips), `assets/brand/` (the two real brand SVGs), `scripts/build-user.command` and `scripts/build-admin.command` (which assets are actually packaged).

---

## Mode: Controlled, against the macOS platform

This is a **macOS menu-bar utility**, and the design is deliberately in **Controlled Mode** against Apple's platform vocabulary rather than Innovative Mode against a blank page. The substrate is the design system: `NSColor` semantic colors, `NSVisualEffectView` materials, SF Pro through SwiftUI's semantic `Font` styles, SF Symbols, and unmodified native control styles. There is no bespoke web-style token layer, no custom hex ramp, no restyled button, no restyled focus ring.

The code proves the commitment rather than merely asserting it. Across all nine files in `native/`, there are **zero `.shadow(` calls**, **zero `repeatForever` animations**, **zero `.tint(` or `.accentColor(` overrides**, **zero `preferredColorScheme` overrides**, and **exactly one literal hex color anywhere — `#2D294E`, and it appears only inside a documentation comment** (`native/models.swift:345`). Every button in the product uses one of the four native styles: `.bordered`, `.borderedProminent`, `.borderless`, `.plain`. Light appearance, dark appearance, Increase Contrast and the user's chosen accent color are all handled by the system because nothing overrides them.

The craft here is not in inventing a look. It is in **restraint, hierarchy, honest status, and the refusal to draw anything that is not true** — and in the one place the product does author its own identity: the menu-bar glyph and its badge vocabulary.

---

## Visual Direction

### Named direction: **Quiet Instrument** (family: **Native Calm**)

The named direction of record is **"Quiet Instrument"** — the visual character of a first-party Apple system utility that lives in the menu bar and speaks like an air-traffic-control panel. Monochrome and silent by default, precise when it has something to say, never decorative. Depth comes from real macOS materials — menu-bar vibrancy, sidebar material, popover blur — and from honest hierarchy, never from drop shadows or fields of color.

The single sentence the whole aesthetic serves: **silence you can trust.** The brightest, most saturated thing on screen is only ever the one thing that is actually wrong. When nothing is wrong, there is nothing to see. This is not minimalism as a style preference; it is the visual expression of the product's core promise, which is that a non-technical person can trust the icon without interpreting it.

**Quiet Instrument** is one register inside a two-app family called **Native Calm**. The sibling register is **"Setup Assistant Calm"** — the do-once, windowed assistant character established by `Publisher Setup.app` and reused verbatim by Control Tower's wizard, Settings and Admin windows: the same `NavigationSplitView` roadmap sidebar, the same card and field and button patterns, the same type scale, the same motion. Quiet Instrument is the register Control Tower adds on top for its always-on face — the menu-bar glyph and the popover. A person who set up a publisher machine and then opens Control Tower should feel the same hand made both.

### The five commitments

| Commitment | The concrete visual move, as shipped | Why it is this way |
|---|---|---|
| **Shape encodes state; color is only ever the second channel** | Every one of the 12 badge tokens maps to an SF Symbol with a unique silhouette, then to a system color (`native/models.swift:56-71`). Strip all color and all 12 states remain distinguishable by silhouette plus their status word. | A status a color-blind person cannot read is a status the product cannot honestly claim to have communicated. The accessibility bar is the design constraint, not a retrofit. |
| **Silence is the success state, drawn as silence** | `BadgeState.none` returns `nil` — the tray draws no badge, no pip, no green, no checkmark (`native/models.swift:58`; `StatusBarController.applyBadge`, `native/control-tower-tray.swift:2600-2617`). The popover's `GlyphView` likewise draws nothing when the state is `.none` (`native/control-tower-tray.swift:1294-1301`). | A green checkmark is a reward for the app, not information for the person. Healthy is the absence of a mark, so the glyph you cannot distinguish from "off" is the glyph saying everything is fine. |
| **Native, not branded-native** | System semantic colors only; `NSVisualEffectView .popover` material for the popover (`native/control-tower-tray.swift:1265-1280`); `.listStyle(.sidebar)` for both roadmap sidebars; semantic `Font` styles; unmodified native controls. | It should look like it shipped with macOS. That is a trust signal for an always-on background agent in a way that a distinctive brand skin actively is not. |
| **Holding states get more design attention than the happy path** | Six distinct setup-row shapes (`native/wizard.swift:5648-5669`), seven distinct Admin run-row shapes (`native/admin-support.swift:1037-1053`), a nine-variant Holding screen family with its own eyebrow tints (`native/wizard.swift:465-510`). The happy path is a plain row with a quiet dot. | Every product designs its success screen. This product's value is entirely in what it does when something is wrong, unknown, or not yet true. |
| **No fabricated progress, ever** | The one continuous motion in the product is an indeterminate `ProgressView` wrapped as `CTNamedWaitSpinner`, which carries the **name of what it is waiting on** and no position (`native/wizard.swift:341-350`). There is no percentage, no ETA, no countdown, no progress bar anywhere. A `notStarted` row has no branch that can reach a spinner (`native/wizard.swift:5599-5626`). | A progress bar that is not driven by real progress is a lie told to make waiting feel shorter. The product names the phase instead. |

### The mark, and the ratified brand rule

The brand rule is **ratified and non-negotiable**:

- **The Control Tower illustration is the logo.** `assets/brand/control-tower-logo.svg` — a full-color 128×128 illustration of a control tower (orange and yellow beacon over a teal-and-slate structure). It is the app icon (shipped as `src-tauri/icons/icon.icns`, copied to `Contents/Resources/ControlTower.icns` by `scripts/build-user.command:115`) and it is the wizard welcome hero at 40pt (`native/wizard.swift:3741-3748`), rendered full-color and never tinted.
- **The aviator sunglasses glyph is the menu-bar mark, always.** `assets/brand/aviator-glyph.svg` — the sunglasses silhouette, authored in brand navy `#2D294E`, packaged into every bundle (`scripts/build-user.command:116`, `scripts/build-admin.command:105`) and loaded as a **template image** at 16pt (`AviatorGlyph.load(targetHeight: 16)`, `native/models.swift:359-395`; applied at `native/control-tower-tray.swift:2556`). Because `isTemplate = true`, macOS discards the asset's own navy and renders the silhouette in the correct menu-bar foreground color: dark in light menu bars, white in dark menu bars, inverted while the item is open. There is deliberately **no substitute-symbol fallback** — a missing asset may never silently replace the product's settled menu-bar identity, so the loader returns a blank template rather than an `eyeglasses` SF Symbol, and packaging tests require the resource in every `.app`.
- **The two marks never trade places.** The aviator glyph is menu-bar-only; nothing else in the app draws it. The popover header explicitly does not (`native/control-tower-tray.swift:1288-1293`) and neither does the wizard roadmap sidebar (`native/wizard.swift:3502-3509`), both of which carry the owner-directive comment in code. Conversely, the full-color illustration is never used at menu-bar scale, because at roughly 20pt and below its detail collapses into an unreadable colored blob — a finding recorded in the loader's own doc comment (`native/models.swift:405-412`) and honored by both call sites, which draw no brand image at all rather than draw a bad one.

Brand navy `#2D294E` is **not a UI color**. It survives only as the fill inside the one SVG asset, and that fill is thrown away at runtime by the template flag. There is no navy bar, no navy banner, no navy card, no navy button. Primary actions use `.controlAccentColor` — the **user's** system accent — never the brand color.

---

## Anti-Direction

### Named anti-direction: **The Alert Machine**

The named failure mode is **The Alert Machine** — the health-score dashboard that mistakes activity for information. It is one of the four anti-patterns held in `SOUL.md` §4, and its visual signature is precise: a gauge or ring or score that aggregates truth into a number, a badge that exists so the person can clear it, a colored banner that celebrates, a notification for every event regardless of whether the reader can act on it. Its close cousin is **The Second Pilot** — the app computing a verdict it has no right to compute, whose visual tell is any surface that renders a state the CLI did not report.

**Why this specific anti-direction and not a generic "avoid clutter":** every alert a non-technical person cannot act on burns down the credibility of the one that matters. A dashboard that is always slightly amber trains people to ignore amber. A green checkmark on a layer that was never actually verified is not a design flourish, it is a false claim. The visual language has to make the honest state easier to draw than the flattering one.

| Rejected on sight | Why it betrays this product |
|---|---|
| **Health scores, rings, gauges, sparklines, percentages** | They aggregate away the one fact the person needs. The Admin preflight header shows a plain count ("2 must be fixed, 1 could not be checked"), never a score. |
| **A green checkmark or celebratory state for "everything is fine"** | Healthy is drawn as the absence of a mark. `BadgeState.none` returns `nil`; the popover glyph view draws an empty `ZStack`. Silence is the reward. |
| **Any state rendered green that was not actually verified** | An entitled-but-not-synced layer renders as a neutral hollow ring, never green and never as an alarm. An unknown preflight check renders `questionmark.circle` in orange with the words "Not checked" — never green. |
| **ETAs, countdowns, percentage bars, fabricated phase pacing** | The prior implementation paced fake phases with `Task.sleep` *after* the real call had already returned. That defect is named in code (`native/wizard.swift:352-359`) and the replacement is a named-subject indeterminate spinner. |
| **A purple or indigo-to-pink gradient, glow, or "AI shimmer"** | The AI-slop signature. It performs an intelligence the app deliberately does not have — it is the tower, not the pilot. Also structurally impossible here: no gradient exists in the codebase. |
| **A filled navy or purple header bar, colored popover header, navy card** | Owner-sourced hard constraint. The brand color exists only as a template tint that the system immediately discards. |
| **Drop shadows used as decoration** | Zero `.shadow(` calls exist in `native/`. Every shadow in the product is drawn by the system, because it belongs to a real `NSPopover`, `NSPanel` or sheet. Depth is material and layering, not paint. |
| **Raw technical strings on a user surface** | No YAML, no git conflict markers, no serde errors, no stage identifiers, no SF Symbol names in VoiceOver labels. Every failure renders as a plain sentence plus a real next step. |
| **A chat box in the menu bar** | The Copilot of the Copilot. A model-driven surface contradicts parse-never-compute by definition and invites exactly the computed judgment the product exists to refuse. |
| **Em-dashes in user-facing copy** | A standing copy constraint carried through the whole design record. |

---

## Design Tokens

Tokens here are **roles mapped onto system values**, not a private palette. The role name is the design vocabulary; the `NSColor` / SwiftUI `Font` on the right is what the code actually writes. This is what makes light mode, dark mode, Increase Contrast and the user's accent free rather than a maintenance burden.

### Colors

#### Neutral roles — surface, content, separators

| Role token | Implemented as | Where it is used | Evidence |
|---|---|---|---|
| `content.primary` | `.labelColor` | Popover status sentence, component names, row titles, mono blocks | `control-tower-tray.swift:1530,1369,1417` |
| `content.secondary` | `.secondaryLabelColor` | Host name, body copy, group labels, layer detail, neutral badge tint | `control-tower-tray.swift:1536,1551,1572` |
| `content.tertiary` | `.tertiaryLabelColor` | Captions, quiet passing dot, not-started rows, offline note | `control-tower-tray.swift:1336,1672`; `wizard.swift:5641` |
| `content.quaternary` | `.quaternaryLabelColor` | The honest empty slot for a layer the CLI reported no checker for at all | `control-tower-tray.swift:1341` |
| `surface.window` | `.windowBackgroundColor` | Wizard, Settings and Admin content pane base | `wizard.swift:3488,3631`; `user-settings.swift:468`; `admin.swift:1616` |
| `surface.card` | `.controlBackgroundColor` | All grouped cards; at 0.5 / 0.58 / 0.72 opacity for nested cards inside cards | `wizard.swift:6471`; `admin.swift:481`; `user-settings.swift:597,902` |
| `surface.field` | `.textBackgroundColor` | Mono code and handoff blocks | `admin.swift:501,1836` |
| `separator` | `.separatorColor` | Hairline `Divider()`; at 0.35 opacity as the owner-chip fill | `admin.swift:532`; `wizard.swift:5066` |
| `accent` | `.controlAccentColor` | Current roadmap pill at 12% opacity, current roadmap glyph, in-flight setup row | `wizard.swift:3551,3567,5655` |

The **popover is not a flat fill**. It is a real `NSVisualEffectView` with `material = .popover`, `blendingMode = .behindWindow`, `state = .active` (`native/control-tower-tray.swift:1265-1280`), applied as the popover root background (`:1506`). Under Reduce Transparency the system falls back to an opaque color automatically, and nothing in the app overrides that.

#### The status ramp — five accents, deliberately scarce

This is the entire chromatic vocabulary of the product. Counted across all of `native/`: `.systemRed` 35 uses, `.systemGreen` 28, `.controlAccentColor` 21, `.systemOrange` 13, `.systemBlue` 8. There is no sixth color.

| Status color | Meaning it is allowed to carry | Why this color, in this product |
|---|---|---|
| `.systemGreen` | Verified-and-current, at row level only | The single quietest confirmation. Never the tray glyph, never a fill, never a banner. A green mark means the CLI actually reported evidence for that layer. |
| `.secondaryLabelColor` (neutral gray) | Setup needed, waiting on IT, waiting for network, offline, not joined, could-not-check, updating | Gray dominates the ramp by design. Most non-healthy states are not emergencies — they are invitations, or somebody else's job, or transient. Rendering them gray is the honest reading. |
| `.systemBlue` | Actionable by *you* — needs sign-in, update available, needs setup | Informational blue, not alarm. Blue in this product means "there is a thing here you personally can do." |
| `.systemOrange` | Needs attention, deferred, could-not-finish, no answer, unknown-never-green | The single amber. It means "look at this," and it is deliberately also the color of *unknown*, so an unverified check can never be mistaken for a pass. |
| `.systemRed` | The CLI could not be read; a run failed; a run refused | Honest hard failure and hard refusal. In the tray this is unique to `bang` — "I won't guess." |

#### Badge vocabulary — the tray marks per state

This is the closed 12-token set. It is the product's one authored piece of iconography, and it is the source of truth for the menu-bar glyph badge, the popover header glyph, and the Holding screen marks. Implemented as `BadgeState.symbolAndColor` (`native/models.swift:40-71`).

| Token | SF Symbol | Color | Silhouette class (grayscale-distinct) | State it names |
|---|---|---|---|---|
| `none` | *(no badge drawn)* | — | absence | Everything is set up. Silence is the success state. |
| `pass` | `circle.fill` | `.systemGreen` | small solid dot | Row-level ready. Never the tray. |
| `hollow` | `circle` | `.secondaryLabelColor` | open unfilled ring | Setup needed, or entitled-but-not-joined. An invitation, not a fault. |
| `wrench` | `wrench.adjustable` | `.secondaryLabelColor` | tool | Waiting on your organization's setup. Not yours to fix. |
| `clock` | `clock` | `.secondaryLabelColor` | dial and hands | Waiting for the network. Nobody's fault. |
| `cloud-slash` | `cloud.slash` | `.secondaryLabelColor` | cloud with slash | Offline. |
| `ring` | `arrow.triangle.2.circlepath` | `.labelColor` | two circular arrows | Syncing. Work in progress is not a severity, so it takes the plain glyph color and no ramp color at all. |
| `key` | `key.fill` | `.systemBlue` | key | Needs sign-in. Yours to do. |
| `update` | `arrow.down.circle` | `.systemBlue` | down-arrow in a circle | An update is available. Informational; transport handles it. |
| `triangle` | `exclamationmark.triangle.fill` | `.systemOrange` | filled triangle | Needs attention. |
| `spinner` | `square.and.arrow.down` | `.secondaryLabelColor` | box with down-arrow | Updating Control Tower itself. |
| `bang` | `exclamationmark.circle.fill` | `.systemRed` | filled circle with `!` | Cannot read the setup helper. The honest degrade. |

**The collision check that matters.** The two "!" states are a filled **triangle** and a filled **circle** — different silhouettes in pure monochrome. The three transport-ish states are **two circular arrows** (syncing), a **down-arrow in a circle** (update available), and a **box with a down-arrow** (updating the app) — three distinct shapes. No two badges in the set share a silhouette, which is what makes the grayscale proof hold.

**How the tray composites it.** The base is always the same aviator template silhouette at 16pt. State is a **9pt SF Symbol badge composited at the bottom-trailing corner** of the status item button, positioned at `x = button.width − 9 − 1, y = 1`, with `SymbolConfiguration(pointSize: 9, weight: .semibold)` and `contentTintColor` set to the badge's system color (`native/control-tower-tray.swift:2600-2617`). When the state is `none`, `symbolAndColor` returns `nil` and the method returns before creating any subview — the bare silhouette is drawn and nothing else. The status item's accessibility label is the current status **sentence**, never the symbol name (`:2597`).

#### Second-tier semantic sets

The windowed surfaces carry their own small closed sets, each built from the same five accents. Documenting them separately is deliberate: they are not the tray vocabulary and a future session should not merge them by accident.

**Settings tier status** — `UserSettingsTierKind` (`native/user-settings.swift:40-65`):

| Kind | Symbol | Color |
|---|---|---|
| `ready` | `checkmark.circle.fill` | `.systemGreen` |
| `needsSetup` | `wrench.adjustable` | `.systemBlue` |
| `needsAttention` | `exclamationmark.triangle.fill` | `.systemOrange` |
| `notJoined` | `circle` | `.secondaryLabelColor` |
| `couldNotCheck` | `questionmark.circle` | `.secondaryLabelColor` |

**Wizard setup-row states** — six distinct shapes for six distinct sentences (`native/wizard.swift:5648-5669`, text at `:5628-5645`):

| State | Symbol | Color | Sentence |
|---|---|---|---|
| `notStarted` | `circle` | `.tertiaryLabelColor` | "Not started yet." |
| `working` | `circle.inset.filled` | `.controlAccentColor` | "Working on it now." (plus a named spinner) |
| `done` | `checkmark.circle.fill` | `.systemGreen` | CLI-supplied detail |
| `deferred` | `clock.badge.exclamationmark` | `.systemOrange` | CLI-supplied detail |
| `couldNotFinish` | `exclamationmark.triangle.fill` | `.systemOrange` | CLI-supplied detail |
| `neverReported` | `questionmark.circle` | `.secondaryLabelColor` | "Setup didn't say what happened here." |

**Admin run-checklist states** — seven shapes (`native/admin-support.swift:1037-1053`, text at `:1056-1066`): `notStarted` `circle` tertiary · `working` / `workingSlow` a `RunWorkingIndicator` · `done` `checkmark.circle.fill` green · `failed` `xmark.circle.fill` red · `refused` `hand.raised.circle.fill` red · `noAnswer` `exclamationmark.triangle.fill` orange · `neverReported` `questionmark.circle` secondary. The `refused` mark being its own shape is load-bearing: "setup stopped here on purpose, nothing after this was changed" is a different fact from "this failed," and the visual system refuses to blur them.

**Roadmap marks** — shared by the wizard sidebar and the Admin sidebar (`native/wizard.swift:3560-3574`; `native/admin.swift:1580`): `done` `checkmark.circle.fill` `.systemGreen` · `current` `circle.inset.filled` `.controlAccentColor` · `upcoming` `circle` `.tertiaryLabelColor` · Admin adds `partial` `circle.lefthalf.filled` with a count.

**Holding screen eyebrow tints** — `HoldingVariant.tint` (`native/wizard.swift:481-489`), which is the only place a *headline* is allowed to take color: `notInstalled` / `waitingOffline` / `waitingBusy` / `waitingOnOrg` → `.secondaryLabelColor` · `unreadable` → `.systemRed` · `fault` → `.systemOrange` · `yours` / `needsPermission` → `.systemBlue`. Each variant also carries a `BadgeState` from the closed tray vocabulary (`:500-510`), so a Holding screen and the tray glyph agree on shape.

**Project triage categories** — five, each with its own symbol (`native/wizard.swift:209-217`): `ready` `checkmark.circle` · `safeFinish` `plus.circle` · `guidedSetup` `arrow.right.circle` · `ownerDecision` `person.crop.circle` · `couldNotConfirm` `questionmark.circle`.

### Typography

**Family:** SF Pro, reached exclusively through SwiftUI's **semantic `Font` styles** rather than point sizes, so Dynamic Type and SF optical sizing work without intervention. There is no second font family and no third. The only design-variant used is `.monospaced()` / `design: .monospaced`, applied to values a person may need to copy or compare character by character.

**Two registers.** The **popover register** is compact — `.headline` down to `.caption2`. The **window register** (wizard, Settings, Admin) is roomy — `.largeTitle` down to `.caption2` — and is inherited verbatim from `Publisher Setup.app` so the two apps read as one family.

| Role | SwiftUI Font | Weight / color | Where | Evidence |
|---|---|---|---|---|
| Settings hero | `.largeTitle` | `.semibold` | "Your setup" | `user-settings.swift:477,483,498` |
| Step / pane title | `.title` | `.semibold`, `content.primary` | Every wizard step H1 | `wizard.swift:3447` |
| Verdict line | `.title2` | `.semibold` | Settings verdict; wizard sub-headlines | `user-settings.swift:502` |
| Section header | `.title3` | `.semibold` | Settings card titles, failure headline | `user-settings.swift:485,897` |
| Popover status sentence | `.headline` | default weight, `content.primary`, wraps | Region 1, the one honest line | `control-tower-tray.swift:1529` |
| Sidebar app label | `.headline` | `content.primary` | Wizard roadmap eyebrow | `wizard.swift:3511` |
| Body / step intro | `.body` | `.regular`, `content.secondary`, `.lineSpacing(2)` | Wizard intros, Settings body | `wizard.swift:3454-3455` |
| Component row name | `.body` | `.semibold`, `content.primary` | Popover component rows | `control-tower-tray.swift:1368` |
| Roadmap row | `.body` | `.medium` when current, `.regular` otherwise | Both roadmap sidebars | `wizard.swift:3545` |
| Host name | `.subheadline` | `.regular`, `content.secondary` | Under the status sentence | `control-tower-tray.swift:1535` |
| Row title | `.callout` | `.semibold`, `content.primary` | Setup rows, component cards, confirm rows | `wizard.swift:5611`; `user-settings.swift:588` |
| Helper text | `.callout` | `.regular`, `content.secondary` | Explanatory lines under a heading | `user-settings.swift:547` |
| Group label / eyebrow | `.caption` | `.semibold`, uppercase, `content.secondary` (wizard eyebrow takes `tint`) | "YOUR COPILOTS", "AVAILABLE TO JOIN", card titles, "STEP N OF 9" | `control-tower-tray.swift:1550`; `wizard.swift:3441-3443,6463-6465`; `admin.swift:473-475` |
| Caption | `.caption` | `.regular`, `content.secondary` or `content.tertiary` | Row state lines, hints | `wizard.swift:5614` |
| Quietest detail | `.caption2` | `.regular`, `content.tertiary` | Sub-captions, subtitle under a group label | `control-tower-tray.swift:1605-1606` |
| Mono value (block) | `.system(.body, design: .monospaced)` | `content.primary` on `surface.field`, selectable | Handoff blocks, copyable code | `admin.swift:496-502` |
| Mono value (inline) | `.caption.monospaced()` / `.system(.caption, design: .monospaced)` | `content.secondary` / `content.tertiary` | Repository paths, run evidence | `user-settings.swift:536`; `admin-support.swift:1014` |
| Mono value (hero) | `.title3.monospaced()` | `content.primary` | The device-flow `user_code` — the one value a person must read aloud or type | `wizard.swift` (2 uses) |

**The one documented exception to "semantic styles only."** SF Symbol *marks* are sized with explicit point sizes, because a symbol's optical size is a geometry decision, not a text-legibility decision: the popover header badge is `.system(size: 14, weight: .semibold)` (`control-tower-tray.swift:1297`), layer dots and join-row marks are `.system(size: 9)` (`:1332,1340,1405`), the menu-bar badge is `SymbolConfiguration(pointSize: 9, weight: .semibold)` (`:2608`). No *text* in the product uses `.system(size:)`.

**Wrapping.** `.fixedSize(horizontal: false, vertical: true)` is applied to every sentence that must survive the largest accessibility sizes — the status sentence, step titles, intros, row detail lines. Text wraps; it does not clip and it does not truncate the one honest line.

### Spacing & Layout

**The real scale, as used.** `2 · 3 · 4 · 5 · 6 · 7 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 24 · 28 · 32`. This is a **2pt-resolution scale**, denser than the 4/8/12/16/24/32/48 scale declared in the visual system of record. The small odd values (3, 5, 7) appear only as internal padding inside compact popover sub-cards, where a 2pt adjustment is the difference between a row reading as one unit and reading as two. This is optical micro-adjustment, and it is recorded here as fact rather than smoothed away — see §9.

| Surface | Outer inset | Section rhythm | Row rhythm | Evidence |
|---|---|---|---|---|
| **Popover** (compact) | 12 horizontal per region, 12 vertical on the root | 12 between regions, each separated by a `Divider()` | 8 within a row, 2–4 within a stacked label | `control-tower-tray.swift:1463,1503,1525-1541` |
| Popover sub-cards | 6–8 padding | — | — | `:1928,2117,2237` |
| **Wizard** (roomy) | 32 horizontal, 24 top, 24 bottom; content column capped at `maxWidth 600` | 24 between sections | card padding 16, internal spacing 12 | `wizard.swift:3462-3465,3435,6469` |
| Wizard footer bar | 32 horizontal, 16 vertical | 12 between actions | — | `wizard.swift:3483-3484,3478` |
| Wizard sidebar row | 12 horizontal, 8 vertical | — | 8 between glyph and label | `wizard.swift:3549-3550,3542` |
| **Settings** | 28 | 20 between cards | card padding 18, internal spacing 14; component card padding 14; tier row spacing 10 | `user-settings.swift:465,450,900,895,596,603` |
| **Admin** | card padding 16, internal spacing 10 | — | chip padding 8 × 3; mono block padding 12 | `admin.swift:479,470,530-531,499` |

**Radii.** All `.continuous` (the macOS squircle), never the default sharp `cornerRadius`.

| Radius | Where | Character |
|---|---|---|
| **6** | Owner chips, the current-roadmap pill | Subtle. A chip is a label, not a control. |
| **7–8** | Compact popover sub-cards, mono / code blocks | Tighter than a card because it sits *inside* one. |
| **10** | The standard card everywhere — wizard `sectionCard`, `AdminCard`, Settings component cards | The macOS grouped-content rounding. This is the family value, shared with Publisher Setup. |
| **12** | The Settings top-level card | Slightly softer for the largest container in the product. |
| **system default** | Every button, text field, picker, switch | **Never restyled.** Native rounding is the nativeness signal, and overriding it is the single fastest way to make a Mac app look like a web app in a costume. |
| **50%** | Status dots (`Circle()` at 6pt) | Standard status pip. |

**Elevation and materials — the honest spatial model.** Depth is material and layering, never paint. The app authors **zero shadows**; every shadow visible in the product is drawn by the system because the thing casting it is a real `NSPopover`, `NSPanel`, or sheet.

| Layer | Material | Shadow | Where |
|---|---|---|---|
| Ground | `.windowBackgroundColor`, opaque | none | Wizard / Settings / Admin content pane |
| Sidebar / chrome | `.listStyle(.sidebar)` vibrancy | none | Wizard and Admin roadmap sidebars |
| Card on ground | `.controlBackgroundColor`, flat | none | Every card, every row group |
| Card inside a card | `.controlBackgroundColor` at 0.5 / 0.58 / 0.72 opacity | none | Nested groups; the opacity step *is* the depth cue |
| Floating instrument | `NSVisualEffectView .popover`, `.behindWindow`, `.active` | system popover shadow | The menu-bar popover |

The nested-card opacity ladder is worth naming as a technique: rather than stacking shadows to signal "inside," the product reduces the card fill's opacity so more of the parent surface shows through. It reads as recession, it costs nothing, and it degrades correctly under Reduce Transparency.

**Surface dimensions, as shipped.**

| Surface | Width | Height | Notes |
|---|---|---|---|
| **Popover** | **360 fixed** | content-sized, grows and scrolls | `.transient`, `animates = true`, `preferredEdge: .minY`; Healthy renders only Regions 1–2 (`control-tower-tray.swift:1504,2564-2566,2637`) |
| **Wizard** | min **820**, ideal **960** | min **620**, ideal **720** | Sidebar min 240 / ideal 260 / max 280; `.navigationSplitViewStyle(.balanced)`; window opens at 960 × 720 (`wizard.swift:3630,3620,3629,7083`) |
| **Settings** | min **760**, ideal **820** | min **650**, ideal **760** | A single scrolling window, not a tabbed Settings scene; opens at 820 × 760 (`user-settings.swift:467,941`) |
| **Admin** | min **1000**, ideal **1080** | min **680**, ideal **760** | Sidebar min 240 / ideal 260 / max 300; opens at 1080 × 760 (`admin.swift:1615,1604`; `admin-support.swift:2104`) |
| Menu-bar item | `NSStatusItem.variableLength` | 16pt glyph, 9pt corner badge | `control-tower-tray.swift:2545,2556,2605` |

**Touch and pointer targets.** Native control heights throughout; `.controlSize(.small)` is used for in-row secondary actions (27 places across the product) so a row stays one line without the button dominating it. Icon-only and disabled controls carry a `.help()` tooltip that states the *reason* rather than just the name — for example a disabled "Join" reads "Waiting for the network." or "Finishing an update first." (`control-tower-tray.swift:1562-1566,1422`).

### Motion

Motion in this product is **confirmation, never attention-getting**, and no motion is load-bearing: every animated state is fully legible frozen, because the shape carries it.

| Interaction | Treatment | Reduce Motion |
|---|---|---|
| Wizard step to step | `.opacity` combined with `.move(edge: .trailing)`, `.easeOut(duration: 0.2)` | Cross-fade only, `.easeOut(duration: 0.15)` — branched explicitly on `@Environment(\.accessibilityReduceMotion)` (`wizard.swift:3582,3626-3627`) |
| Admin run-row state change | `.easeInOut(duration: 0.15)` | Opacity-only by nature (`admin-support.swift:1031`) |
| Project card selection | `.easeOut(duration: 0.15)` | Opacity-only by nature (`wizard.swift:4400`) |
| Popover open / close | System `NSPopover` animation (`animates = true`) | System-handled |
| Any wait | Indeterminate `ProgressView` at `.controlSize(.small)`, wrapped as `CTNamedWaitSpinner` with the **name of the subject** as its accessibility label | System-handled |
| Copy confirmation | Label swaps to "Copied" and back after **2.0s**; never a toast (`admin.swift:504-515`) | Text change only |

Three facts define the motion posture: there are **four `.animation` / transition call sites in the entire product**, there are **zero `repeatForever` animations**, and the reduce-motion branch is written explicitly rather than left to the system. Nothing loops, nothing pulses to get noticed, nothing bounces.

---

## Component Patterns

### The menu-bar item — the always-on face

An `NSStatusItem` at `variableLength` whose image is the aviator template glyph at 16pt, with `imagePosition = .imageOnly` and both left- and right-mouse-up routed to one action (`control-tower-tray.swift:2554-2562`). Left-click refreshes and toggles the popover; right-click builds a minimal `NSMenu` — **Sync now**, **What changed**, **Settings...** (⌘,), then in the Admin build only, **Open Administration...** behind `#if CT_ADMIN_BUILD`, then **Quit** (`:2656-2689`). The menu is attached and immediately detached so the next left-click still opens the popover. "Sync now" is disabled while syncing or offline, using the same honest-disable discipline as the popover.

State reaches the glyph as a composited 9pt corner badge and as the accessibility label, which is the status **sentence**. The background poll is a single `Timer` at **300 seconds** (`:2536,2584-2590`); refresh also runs on launch and on every popover open, so the popover can never show stale data at the moment a person actually looks at it.

### The popover — six stacked regions, drawn only when they carry information

Root: `VStack(alignment: .leading, spacing: 12)`, fixed width 360, `.padding(.vertical, 12)`, `.fixedSize(vertical)`, on the `.popover` material (`control-tower-tray.swift:1462-1506`). Every region is `.padding(.horizontal, 12)` and separated by a `Divider()`. **A region renders only when it has something to say** — Healthy shows Regions 1 and 2 and nothing else, and the `cli-unreadable` state shows the header sentence plus the retry action and deliberately draws no tree and no join row at all.

1. **Status header** (always). `HStack(spacing: 8)` of `GlyphView` (a 20 × 20 frame containing the 14pt badge mark, or nothing when the state is `none`) plus a `VStack(spacing: 2)` of the `.headline` status sentence over the `.subheadline` host name. The sentence carries `.accessibilityAddTraits(.updatesFrequently)` so a change announces politely without stealing focus. While a sync is in flight the sentence swaps to "Bringing everything up to date…" and the glyph swaps to `ring` (`:1516-1542`).
2. **`YOUR COPILOTS`** — one row per CSE component. Row = `.body .semibold` component name, a trailing `.caption .semibold` verdict word ("Ready" / "Needs review" / "Needs attention") colored green only when passing, then a `.caption` layer summary line and, when something is not passing, a `.caption2` tertiary detail (`:1361-1389`). The four layers render as a fixed four-column grid of `LayerDot`s, so an absent layer still gets its own slot rather than silently collapsing the row: passing is a 6pt `.tertiaryLabelColor` dot (never the colorful `pass` mark — that would be the green-checkmark reward the copy rules forbid), non-passing is the badge shape, and a layer with no checker at all is a `circle` in `.quaternaryLabelColor` whose tooltip reads "You're not in this one" (`:1315-1358`). Layer names render in plain words — "Core setup", "Your organization", "Your department", "This Mac" — never the internal layer identifiers.
3. **`AVAILABLE TO JOIN`** — present only when a joinable entry exists. Row = a 9pt hollow `circle` in `.secondaryLabelColor`, the department name, and a native `.bordered` **Join** button. The joining state replaces the name with "Joining <name>…" and a named spinner; a failure becomes a plain sentence with **Join** restored. Never a bright badge, never green, never an alarm (`:1393-1441,1568-1583`).
4. **Integrations** — two labeled registers. `SHARED WITH YOUR TEAM` with the subtitle "Ready for you. Nothing to sign into." carries **no rows with controls, ever** — the absence of a sign-in affordance is the design. `YOUR ACCOUNTS` carries the GitHub row with its real state from `auth status` (`:1599-1622`).
5. **Action row** — `Sync now` as `.bordered`, then `What changed`, conditionally `Set up`, and `Settings…` as `.borderless`. `Sync now` disables while syncing or offline and an honest `.caption` "Waiting for the network." appears beneath. There is deliberately **never an "Update" button**: updates install themselves (`:1632-1676`).
6. **Notice lane** — at most one *prompt* (the unsaved-changes hold, else the permission prompt), then independently any number of *notices*. The prompt is a `.callout` sentence plus exactly one affordance, and there is no discard control anywhere in it — never-destroy, expressed as a missing button (`:1692-1710`).

### The window shell — `StepShell` plus the roadmap sidebar

`NavigationSplitView` with `.navigationSplitViewStyle(.balanced)`: a non-collapsible `.listStyle(.sidebar)` roadmap at 240 / 260 / 280, and a content pane on `surface.window` (`wizard.swift:3618-3631`).

`StepShell` is the one content anatomy every wizard step uses (`:3392-3489`): **eyebrow** (`.caption .semibold`, uppercase, tinted — `.systemBlue` by default, or the Holding variant's own tint) → **title** (`.title .semibold`) → **intro** (`.body`, secondary, `.lineSpacing(2)`) → **content** → a pinned footer bar with leading actions, a spacer, and one trailing primary. The content column is capped at `maxWidth: 600` and centered in a 32pt inset, which is what keeps a 960pt-wide window readable. A `ScrollViewReader` scrolls back to the top on every title change, so a step never opens mid-page.

The roadmap sidebar shows **all nine stages** at all times with done / current / upcoming marks (`:3496-3575`). The current row is an `.controlAccentColor` fill at **12% opacity** clipped to a radius-6 pill — the one authored fill in the product, and it is 12% precisely so it reads as a highlight and not as a selected-row chrome. Completed rows are tappable for review; upcoming rows are disabled and drawn at 0.5 opacity. Each row's accessibility label is the full sentence "Step N of 9, <title>, <status word>". The sidebar deliberately draws **no brand image**: the aviator glyph is tray-only, and the full-color illustration is illegible at 16pt, so the text alone is the eyebrow — a decision recorded in code.

The nine stages, in their shipped order and with their shipped titles (`wizard.swift:62-79`): Welcome → Connect GitHub → Detect → What you're getting → Departments → **Your connections** → **Your projects** → **Set up** → Verify.

### Card grammar — one pattern, three implementations

The card is the product's workhorse container and it is the same shape everywhere: an uppercase `.caption .semibold` secondary title, the content, `.padding(16)`, `.controlBackgroundColor`, radius **10** `.continuous`, full width, leading-aligned.

- **`sectionCard`** (`wizard.swift:6459-6473`) — internal spacing 12.
- **`AdminCard`** (`admin.swift:460-484`) — internal spacing 10, title optional.
- **`settingsCard`** (`user-settings.swift:891-904`) — the outlier: a `.title3 .semibold` title rather than an uppercase caption, `.padding(18)`, spacing 14, radius **12**, because these are the three top-level containers of the whole Settings window rather than sub-groups inside a step.

### Row patterns

**Disclosure component row** (Settings, `user-settings.swift:561-600`) — a `DisclosureGroup` whose label is a kind symbol, a `.callout .semibold` component name, a spacer, and a `.caption .semibold` verdict word in the kind's color; the card itself is `.padding(14)` on `controlBackgroundColor` at 0.58 opacity, radius 10. Disclosed content is a `Divider()`-separated stack of tier rows.

**Tier row** (`:602-620`) — `HStack(alignment: .top, spacing: 10)` of a 16pt-wide kind symbol, a `VStack(spacing: 2)` of `.caption .semibold` label over `.caption2` secondary detail, a spacer, and the `.caption .semibold` state word in the kind's color. **The state word is always printed** — the color is redundant with it, never a substitute for it.

**Setup / run row** (`wizard.swift:5604-5626`; `admin-support.swift:1000-1034`) — `HStack(alignment: .top, spacing: 10)` of a 16pt-wide state glyph, a `VStack(spacing: 2)` of `.callout .semibold` title over the `.caption` state sentence in the state's own color, a spacer, and — only in the `working` case — a `CTNamedWaitSpinner`. Six distinct shapes for six distinct sentences. The Admin variant additionally prints monospaced `evidence` in `.tertiaryLabelColor` and, when a run is slow, an extra honest line: "Still working on this one. GitHub can be slow to answer."

**Owner chip** (`admin.swift:523-535`) — `.caption .semibold` secondary text, 8 × 3 padding, `.separatorColor` at 0.35 opacity, radius 6. Used to attribute every preflight row to whoever actually owns fixing it.

**Copyable code block** (`admin.swift:488-519`) — monospaced body text on `.textBackgroundColor`, `.padding(12)`, radius 8, `.textSelection(.enabled)`, with a `.borderedProminent` button whose label becomes "Copied" for two seconds. Never a toast.

### State treatments

Every data-backed surface in the product carries the same five non-default treatments, and the discipline is consistent enough to state as a rule.

| State | Treatment |
|---|---|
| **Loading** | A `ProgressView` at `.controlSize(.small)` beside a sentence naming what is being checked — "Checking every Copilot repository and layer…", "Checking Knowledge, CLI, Claude, and Codex…", "Checking your connections…" (`user-settings.swift:906-913`). Never a skeleton that implies a shape the data may not have. |
| **Could-not-check** | A titled failure block with a plain reassurance — "Nothing was changed, and Control Tower will not call the ecosystem ready without that report." — plus a **Try again** `.bordered` button (`user-settings.swift:480-490`). Never a fabricated value, never a zero rendered as a fact. |
| **Disabled** | Native dimming plus a `.help()` tooltip carrying the *reason*, not the name. |
| **Empty** | The region is **structurally absent** rather than rendered as a blank shell — the join region only exists when something is joinable, the component tree only when components were reported. "What changed" is the exception, with an explicit "Nothing has changed since you last looked." |
| **Error** | A plain sentence and a real next step. Never a raw error string, never a stage identifier, never git or YAML. |

### The Admin surfaces

A single window with a two-section `.listStyle(.sidebar)` source list — **Onboarding** (11 stages) and **Governance** (5 stages), 16 surfaces total — over a detail pane on `surface.window` (`admin.swift:1523-1616`). Each sidebar row carries an SF Symbol and a progress mark. The stage symbols, as shipped (`:560-574,591-599`): `map` · `checklist` · `person.text.rectangle` · `point.3.connected.trianglepath.dotted` · `building.2` · `puzzlepiece.extension` · `lock.doc` · `arrow.left.arrow.right.circle` · `checkmark.seal` · `checklist.checked` · `checkmark.seal`; and for Governance: `person.badge.plus` · `person.badge.minus` · `key.viewfinder` · `list.bullet.rectangle` · `chart.bar.doc.horizontal`.

Admin is visually the same family — same cards, same radii, same type roles, same run-row grammar — at a larger scale (1080 × 760 ideal) because it hosts denser evidence. There is **no fleet dashboard, no MDM surface, no health gauge**; the Analytics governance surface is an opt-in toggle, not a chart of machines.

---

## Accessibility

The accessibility bar is a design input here, not a compliance pass at the end. Three properties carry it.

**Contrast is inherited, not tuned.** Every text color in the product is a system semantic label color on a system background or material. Because nothing is hardcoded, AA contrast holds in light appearance, dark appearance and Increase Contrast automatically, and it will keep holding through OS revisions. Status color never has to carry contrast on its own, because it is never the sole signal.

**Color-independence is provable.** Strip every color from the product and all 12 tray states remain distinguishable by silhouette alone (see the collision check in the badge table), all six setup-row states by shape, all seven Admin run states by shape, and every list and tree row additionally prints its status **word**. The `.systemGreen` dot is redundant with "Ready"; the `.systemOrange` triangle is redundant with the sentence beside it.

**VoiceOver labels name states, never symbols.** The status item announces the status sentence (`control-tower-tray.swift:2597`); component rows announce "<component>, <status>"; layer dots announce "<plain layer name>, <detail>" and, when absent, "You're not in this one"; roadmap rows announce "Step N of 9, <title>, <completed | current | not started>"; setup rows announce "<title>, <state sentence>". Decorative marks are explicitly `.accessibilityHidden(true)` so a screen reader is not read a shape twice. There are 57 explicit `accessibilityLabel` call sites across `native/`.

Dynamic Type is honored through semantic `Font` styles with `.fixedSize(horizontal: false, vertical: true)` on every sentence that must wrap. Reduce Motion is branched explicitly in the wizard transition. Focus rings are the system rings, never restyled. Copyable values carry `.textSelection(.enabled)`. **Secret values are never rendered anywhere**, so they are never announced either.

---

## Known deviations and open items

Recorded honestly rather than smoothed over. These are the places where the shipped code and the design of record differ, or where a documented intent did not land.

| # | Deviation | Status |
|---|---|---|
| **D-1** | **Spacing scale is finer than declared.** The visual system of record declares `4 / 8 / 12 / 16 / 24 / 32 / 48`; the shipped code also uses 2, 3, 5, 6, 7, 10, 14, 18, 20, 28. The additions are almost entirely internal padding of compact popover sub-cards and nested Settings cards. | Real. Documented as the shipped scale above. Not a defect; worth a deliberate reconciliation if the token set is ever formalized in code. |
| **D-2** | **Settings shipped as one scrolling window, not a six-tab `Settings` scene.** The design of record specifies General / Components & Layers / Integrations / Personal Key Sync / Advanced / Administration at ~560–620pt. Shipped: a single 820 × 760 `NSWindow` with a header and three cards — "Your copilots", "Your connections", "Your projects". | Real. The shipped shape is simpler and matches the user's actual mental model; the record is the stale side. |
| **D-3** | **Personal Key Sync (S13) did not ship.** No key-sync tab, roster, or conflict chooser exists in `native/`. | Not built. The design remains in the record as a design-only artifact. |
| **D-4** | **The two-register Shared-versus-Personal integration split is partially rendered.** `SHARED WITH YOUR TEAM` renders its header and subtitle with no rows, because no CLI verb backed a shared-integrations list at v0.3.2. The code comments this honestly rather than fabricating rows. | Honest partial. The `cc connections` bridge that fills this in landed immediately after v0.3.2. |
| **D-5** | **`needsSetup` is blue in Settings, gray in the tray.** The tray's `wrench` badge is `.secondaryLabelColor`; `UserSettingsTierKind.needsSetup` is `.systemBlue` with the same `wrench.adjustable` symbol. | Real divergence. Arguably correct — in Settings the person *is* being invited to act, which is exactly what blue means in this ramp — but it is an inconsistency and should be a deliberate decision rather than an accident. |
| **D-6** | **The wizard welcome hero can fall back to an SF Symbol in a packaged app.** `ControlTowerGlyph` resolves `assets/brand/control-tower-logo.svg` **relative to the working directory only** — it has no `Bundle.main` lookup, unlike `AviatorGlyph` — and `build-user.command` copies only `aviator-glyph.svg` into `Contents/Resources`. In a shipped `.app` the loader therefore reaches its last-resort `building.2` SF Symbol. | Real gap between the brand rule and the packaged artifact. Documentation-only pass: recorded, not fixed. <!-- TODO: confirm on a running 0.3.2 install whether the welcome hero draws the illustration or the building.2 fallback --> |
| **D-7** | **The wizard file header comment says "Step N of 10"; every shipped eyebrow string says "Step N of 9",** and `WizardStage.allCases.count` is 9. | The comment is stale; the strings and the enum agree. Nine is correct. |
| **D-8** | Window minimums drifted upward from the record: wizard 820 × 620 (record: 800 × 600), Admin 1000 × 680 (record: 900 × 640). Popover width 360 matches exactly. | Real, minor. Code wins. |

Open items with no visual answer yet: <!-- TODO: no documented light-versus-dark visual proof exists as an artifact — the system semantic colors make it correct by construction, but there is no captured evidence of both appearances at the largest Dynamic Type sizes --> and <!-- TODO: no motion specification exists for the tray badge itself; the record calls for pulse / ring / spinner animations with distinct static Reduce-Motion shapes, and the shipped tray composites a static badge with no animation at all -->

---

## Visual References

Named references, with what is taken from each and what is deliberately not.

| Reference | What is taken | What is rejected |
|---|---|---|
| **macOS system menu-bar extras** (Wi-Fi, Battery, Time Machine) | The whole posture: a monochrome template glyph, roughly 16pt, that changes shape rather than color to say something, and says nothing most of the time. This is the closest ancestor of the product's tray behavior. | Nothing. This is the model. |
| **Apple's own Setup Assistant / System Settings** | The roadmap sidebar plus content-pane anatomy, the card grammar, the eyebrow-title-intro-content-footer step shell, and the discipline of never restyling a control. | The tone. System Settings is a configuration surface; this product's windows are a guided path with one primary action per screen. |
| **`Publisher Setup.app`** (the sibling in this ecosystem) | Tokens, roadmap-sidebar grammar, card patterns, the type scale, and the motion — reused wholesale so the two apps read as one design team's work. | Nothing structurally; Control Tower extends the family with the menu-bar instrument register that Publisher Setup does not have. |
| **An air-traffic-control panel** | The governing metaphor from `SOUL.md` §2: monochrome and silent, precise when it has something to say, and the brightest mark on the panel is always the truest problem. | The density. A real ATC panel shows everything at once; this product shows only what is currently true and hides the rest. |
| **Little Snitch / Bartender / iStat Menus** (the menu-bar utility neighborhood) | The proof that a serious background utility can live entirely in a popover, and the expectation that a right-click gives a minimal, boring, predictable menu. | Their information density and their configurability. Those tools serve technical operators; this one serves someone who should never have to learn what a layer is. |
| **Any SaaS status dashboard** | Nothing. | Everything: the health score, the uptime ring, the color-coded grid, the "all systems operational" banner. This is the anti-direction rendered as a product category. |

**Sources**

- [Apple HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Apple HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [NSStatusItem, Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsstatusitem)
