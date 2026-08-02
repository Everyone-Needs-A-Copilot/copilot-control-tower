# Native visual refresh — the walkthrough grammar, in SwiftUI terms

**Status:** specification, ready for implementation · **Task:** 222 · **Author:** @agent-uids · **Mode:** Controlled (extends the ratified [`control-tower-visual-system.md`](control-tower-visual-system.md); it does not replace it)

**The brief in one line:** the HTML walkthroughs look considerably better than the shipped app, and the owner wants that gap closed natively without an interface rework. This document is a **styling pass**: one new file of tokens and components, plus mechanical substitutions at existing call sites. No view is restructured, no navigation changes, no model touches `native/`'s architecture.

**Scope note:** this document is docs-only. It cites `native/*.swift` at specific lines as evidence and as the target of each change; it does not modify them.

---

## 0. Why the app reads worse — the diagnosis, measured

The walkthroughs and the app were built from the same ratified design language, so the gap is not a disagreement about design. It is that several of the app's visual decisions **do not render at all**, and several others land two steps below the walkthrough's legibility floor. Everything below was measured on this machine (Darwin 25.5) by rasterizing the semantic colors under both appearances, not estimated.

### G-1 — Every card in the app is invisible. This is the single biggest cause.

`NSColor.controlBackgroundColor` and `NSColor.windowBackgroundColor` resolve to **the identical value** on current macOS: `#FFFFFF` in light, `#1E1E1E` in dark. Measured contrast between them: **1.00:1**. The app draws every card as `.background(Color(nsColor: .controlBackgroundColor))` with **no border and no shadow** — `native/wizard.swift:6526`, `native/user-settings.swift:934`, `native/user-settings.swift:612`, `native/control-tower-tray.swift:1928`. There are **zero** `.stroke(...)` borders on any card anywhere in `native/` (only two strokes exist in the whole tree, both on chips: `native/wizard.swift:5121`, `native/wizard.swift:6586`). So the entire card system — the thing that gives the walkthroughs their structure — renders as a flat, edgeless page. The walkthrough's card is `border:1px solid var(--line); border-radius:10px; background:var(--paper)` on a *tinted page*: the edge is doing all the work, and the app has no edge.

### G-2 — Three different "card" weights, all of which are the same non-card.

`.opacity(0.58)` (8 sites), `.opacity(0.72)` (8 sites), `.opacity(0.5)` (1 site) are applied to `controlBackgroundColor` to suggest a hierarchy of card weights — `native/user-settings.swift:558`, `native/user-settings.swift:895`, `native/control-tower-tray.swift:1945`, `native/control-tower-tray.swift:2118`, `native/control-tower-tray.swift:2237`. Because the fill equals the page, translucent white over white is white: all three weights are byte-identical no-ops. Intent existed; nothing shipped.

### G-3 — Supporting text is both too small and below the contrast floor.

Row description text is `.caption` (10pt) in `.secondaryLabelColor` — `native/wizard.swift:4674`, `native/wizard.swift:4717`, `native/user-settings.swift:757`, `native/user-settings.swift:788`. Measured: `.secondaryLabelColor` on the page is **3.95:1** in light mode, below the 4.5:1 the product's own §9.1 requires. The walkthrough's equivalent (`.row small`) is ~13px at `--muted:#66666d`, measured **5.70:1**. So the app's supporting copy is 3pt smaller and materially fainter than the design it came from. This is why the app reads "washed out" beside the walkthrough.

### G-4 — Load-bearing sentences are drawn in tertiary, at 1.88:1.

`.tertiaryLabelColor` measures **1.88:1** light / **2.26:1** dark. The app uses it for text a person must read to act: the "what is actually missing" line on a `needs-connect` connection row (`native/wizard.swift:4720`, `native/user-settings.swift:791`), the honest-degrade explanation under a `no-store` group (`native/wizard.swift:4746`, `native/user-settings.swift:816`), the "check the values with whoever gave them to you" recovery line in the Connect sheet (`native/user-settings.swift:1099`, `native/user-settings.swift:1111`). Apple ships tertiary as a *decorative* tier. Putting the honesty floor's own sentences there is the accessibility defect with the highest stakes in this app.

### G-5 — Status colors fail contrast in light mode, exactly where the walkthrough passes.

Measured on the light page: `.systemGreen` **2.22:1**, `.systemOrange` **2.31:1**, `.systemRed` 3.57:1, `.controlAccentColor` 4.02:1. These are used as **text** colors — `native/user-settings.swift:634` (the tier status word), `native/user-settings.swift:607`, `native/user-settings.swift:1083`, `native/user-settings.swift:1089`, `native/control-tower-tray.swift:1373`. The walkthrough's ramp is appearance-specific and passes in both: `--ok #2b8547` **4.62:1** light / `#65c77d` **7.95:1** dark; `--warn #9b671e` **4.82:1** / `#e1b462` **8.66:1**. macOS system status colors keep one vivid hue across appearances, which is right for glyphs and wrong for small text on white.

### G-6 — No type hierarchy inside cards; five roles collapse into two fonts.

Inside a card the walkthrough has five distinct roles — card title (11 semibold uppercase, tracked), row title (15/650), row detail (13 muted), status word (12/700), and inline caption. The app renders row title as `.callout.weight(.semibold)` (12pt) and *everything else* as `.caption` (10pt), varying only the color: `native/wizard.swift:4617`/`4620`/`4625`, `native/user-settings.swift:753`/`756`/`761`. Two sizes cannot encode five ranks, so cards read as an undifferentiated stack of small grey sentences instead of a structured group.

### G-7 — Section headers are inconsistent, and half of them are shouted string literals.

Three different treatments for the same rank: `.caption.weight(.semibold)` + `.textCase(.uppercase)` in the wizard (`native/wizard.swift:6518`), `.title3.weight(.semibold)` in title case in Settings (`native/user-settings.swift:929`), and **literal uppercase strings** in the tray — `Text("YOUR COPILOTS")` at `native/control-tower-tray.swift:1549`, `Text("AVAILABLE TO JOIN")` at `1570`, `Text("SHARED WITH YOUR TEAM")` at `1601`, `Text("YOUR ACCOUNTS")` at `1608`. Literal caps ship the shouting to VoiceOver and to any future localization; `.textCase(.uppercase)` does not. None of the three carries letter-spacing, which is what makes the walkthrough's 11px kicker read as a label rather than as cramped small text.

### G-8 — Spacing is ad-hoc, not a scale.

`.padding(N)` uses **13 distinct values** across `native/` — 4, 6, 7, 8, 9, 10, 12, 14, 15, 16, 18, 24, 28. `VStack(spacing:)` uses **14 distinct values** — 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20, 24. Corner radii use six values — 6, 7, 8, 10, 12, 999. There is no scale, so no rhythm; adjacent cards on the same screen sit on different grids and the eye reads the surface as unresolved.

### G-9 — The wizard's step title is a size too small for its job.

`StepShell` draws the step title at `.title` (22pt) and the intro at `.body` (13pt) — `native/wizard.swift:3456`, `native/wizard.swift:3463`. The walkthrough's `h3` is 27px at `letter-spacing:-.025em`, with a 15px lead. That one step is most of the "the walkthrough feels more considered" impression: the walkthrough commits to its headline, the app hedges.

### G-10 — The eyebrow is drawn in raw accent, untracked, at 10pt.

`native/wizard.swift:3449-3452`: `.caption.weight(.semibold)` in the tint, uppercased. At 10pt in `.controlAccentColor` this measures **4.02:1** — under the floor — and without tracking it reads as small blue text rather than as the walkthrough's kicker (`font-size:11px; font-weight:750; letter-spacing:.07em`).

### G-11 — The callout and decision blocks have no native counterpart, so their content is re-improvised each time.

The walkthrough's two highest-value composites — `.callout` (24pt glyph gutter + strong lead + muted body) and `.decision` (fixed ~132pt label column + explanation, hairline-separated) — are the shapes that carry the product's honesty voice. In the app each occurrence is hand-built from a fresh `VStack`/`HStack` with fresh paddings: `native/control-tower-tray.swift:2186-2199`, `native/control-tower-tray.swift:2340-2351`, `native/user-settings.swift:900-910`, `native/wizard.swift` Holding views. Same idea, eight geometries.

### G-12 — The Connect sheet celebrates, which the copy deck forbids.

`native/user-settings.swift:1081-1083` renders `Label("Connected.", systemImage: "checkmark.circle")` in `.systemGreen`. `control-tower-copy-deck.md` hard rule 6 and the walkthrough's floor rule 11 both say silence is the success state and there is no celebration. The receipt for a successful connect should be **the row behind the sheet flipping to Ready**, not a green check inside a sheet that is about to close.

---

## 1. Aesthetic direction

Three candidates were roughed out against the walkthroughs and the macOS constraint set.

**A · Instrument Panel (Swiss Precision).** Everything hairline-ruled, no fills at all, uppercase micro-labels, monospaced numerals, tight vertical rhythm. Fits a supervisor tool conceptually and would be cheap to build. Rejected: it reads cold and technical, and this product's whole voice — "when it has nothing to say, it says nothing", "nothing was changed" — is calm and human. A control-panel aesthetic would argue with the copy on every screen.

**B · Quiet Paper (Editorial Calm).** The walkthroughs' own grammar, taken literally: bordered paper cards on a slightly recessed ground, generous lead paragraphs, one accent used sparingly, muted-but-legible supporting text, uppercase tracked micro-labels. Fits because it *is* the thing the owner already recognizes as better, and because its structure (card → card-title → rows) maps one-to-one onto what the app already builds.

**C · System Native Grouped.** Pure Apple: `Form(.grouped)`, `GroupBox`, `List(.insetGrouped)`, zero custom drawing. Maximum nativeness and free dark mode. Rejected as the whole answer: adopting `Form(.grouped)` means restructuring every step body and every settings section into `Section`/`LabeledContent`, which is precisely the view-architecture rework the brief excludes — and it would flatten the wizard's editorial lead paragraphs into form rows, losing the voice.

### Committed: **Quiet Paper, Native Frame**

B's grammar expressed with C's materials. Every card, label, and rhythm decision comes from the walkthroughs; every colour, control, material, and focus behaviour comes from macOS semantic APIs. The four rules that define it:

1. **The card edge is the structure.** A hairline `separatorColor` border is the primary signal that a card is a card; a 3–5% tint is the redundant second signal. This is native (`NSBox`, `GroupBox`, and `List(.inset)` all draw exactly this edge) and it is the one change that makes the app's existing card intent visible for the first time.
2. **Two text weights of ink, never three.** Anything a person must read is `content.primary` or `content.muted` (both measured ≥ 4.5:1). `content.faint` exists for the actor line and section numbers only, and never carries a fact alone.
3. **Colour is the second channel, always.** Unchanged from the ratified system: shape and word first. What changes is that the colour, when used, must actually be legible — so state colours become appearance-corrected rather than raw system vivid.
4. **The system draws every control, every focus ring, every shadow, every material.** No restyled buttons, no authored shadows, no custom focus. The refresh lives in typography, spacing, card edges, and colour tokens — nowhere else.

**What this direction refuses:** no gradients, no glass panels behind content, no coloured header bars, no card hover lift, no purple/navy fills, no celebration states, no illustration. The walkthroughs contain none of these, and neither will the app.

---

## 2. The token set

All of it lives in **one new file, `native/design-system.swift`**, which must be added to the source list in `scripts/build-user.command:24-30` and to the equivalent list in `scripts/build-admin.command`. Nothing else is added; every consumer is an existing file changing a literal to a token.

### 2.1 Spacing — `CTSpace`

An 8pt grid with two half-steps, reconciling the walkthroughs' CSS values to the nearest native rhythm. It replaces the 13 ad-hoc padding values in G-8.

| Token | pt | Walkthrough source | Use |
|---|---|---|---|
| `CTSpace.hair` | 2 | `.row strong` → `small` gap | Title-to-detail inside a row |
| `CTSpace.xs` | 4 | `gap:5px` | Glyph-to-label, chip internals |
| `CTSpace.sm` | 8 | `gap:7–8px` | Between sibling controls, label-to-field |
| `CTSpace.rowV` | 10 | `.row{padding:10px 0}` | Vertical padding of one list row — the one non-8pt value, kept because 8 crowds a two-line row and 12 loosens the card |
| `CTSpace.md` | 12 | `gap:10–12px` | Between cards, glyph gutter, card-title to first row |
| `CTSpace.lg` | 16 | `.card{padding:15px}` | Card interior padding (default) |
| `CTSpace.xl` | 20 | `.lead{margin-bottom:20px}` | Between groups inside a step |
| `CTSpace.section` | 24 | `section` rhythm | Between major sections of a step body |
| `CTSpace.pane` | 32 | `.content{padding:29px 34px}` | Window content inset (horizontal) |
| `CTSpace.paneTop` | 24 | `padding-top:29px` | Window content inset (top) |
| `CTSpace.hero` | 48 | — | Reserved: Welcome/Done vertical breathing |

**Popover register** (the tray is compact and keeps its own inset): pane inset `CTSpace.md` (12) horizontal, region gap `CTSpace.md` with a hairline between, card padding `CTSpace.md`. Unchanged from `native/control-tower-tray.swift:1503`/`1541` — the tray's spacing was already right; its problem is G-1/G-7, not rhythm.

### 2.2 Radii — `CTRadius`

| Token | pt | Where | Character |
|---|---|---|---|
| `CTRadius.card` | 10, `.continuous` | Every bordered card | The walkthrough's `border-radius:10px`; macOS grouped-content rounding |
| `CTRadius.well` | 8, `.continuous` | Inset wells: callouts, code blocks, the Connect sheet's field group | Tighter than its container, so a nested surface reads as recessed rather than as a second card |
| `CTRadius.chip` | capsule | Chips, pills, the NEW marker | The walkthrough's `border-radius:99px` |
| — | system default | **Buttons, text fields, `SecureField`, pickers, steppers** | Never restyled. Native rounding is the nativeness signal (ratified system §5.3) |

Retires the stray 6, 7, 12, and 999 values from G-8.

### 2.3 Colour — `CTColor`

Two families. **Surfaces and ink** are derived from semantic colours so they follow appearance, accent, and Increase Contrast. **State colours** are semantic system colours with a light-mode correction, because the raw ones fail the product's own contrast rule (G-5).

#### Surfaces

| Token | Definition | Resolves to | Why |
|---|---|---|---|
| `CTColor.page` | `Color(nsColor: .windowBackgroundColor)` | `#FFFFFF` / `#1E1E1E` | Unchanged; the ground stays the system's |
| `CTColor.card` | `Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)` composited over `page` | `#F6F6F6` / `#292929` | Mirrors the walkthrough's paper→panel delta exactly (`#fff`→`#f7f7f8`; `#1c1c1f`→`#252529`). Derived from `Color.primary`, so it inverts with appearance instead of being two hardcoded hexes |
| `CTColor.well` | `Color.primary.opacity(colorScheme == .dark ? 0.095 : 0.065)` over `page` | `#F1F1F1` / `#303030` | The walkthrough's `.card.inset`: one step deeper, reads recessed |
| `CTColor.cardBorder` | `Color(nsColor: .separatorColor)`, 1pt | black @10% / white @10% | The native analogue of `--line`. **This is the load-bearing token of the whole refresh** |
| `CTColor.hairline` | `Color(nsColor: .separatorColor)` | same | Row dividers inside a card (`Divider()` already resolves here) |

The popover keeps `NSVisualEffectView(.popover)` as its ground (`native/control-tower-tray.swift:1267-1280`, `1506`) — unchanged, and correct. Cards *inside* the popover use `CTColor.card`, which composites over the material and stays translucent-aware.

#### Ink

| Token | Definition | Measured light / dark | Rule |
|---|---|---|---|
| `CTColor.ink` | `Color(nsColor: .labelColor)` | 14.94:1 / 12.23:1 | Names, titles, status sentences, anything primary |
| `CTColor.muted` | `Color(nsColor: .labelColor).opacity(0.71)` under standard contrast; `.labelColor` under `.increased` | resolves `#666666` / `#A5A5A5` → **5.74:1 / 6.77:1** | The walkthrough's `--muted` (`#66666d`, 5.70:1) reproduced natively, to the byte. **Replaces `.secondaryLabelColor` for every sentence a person must read** (G-3) |
| `CTColor.secondary` | `Color(nsColor: .secondaryLabelColor)` | 3.95:1 / 5.89:1 | Retained for **≥13pt supplementary text only** — text that may be skipped without losing a fact |
| `CTColor.faint` | `Color(nsColor: .labelColor).opacity(0.66)` | resolves `#707070` / `#9C9C9C` → **4.95:1 / 6.07:1** | Actor lines, step numbers, unit suffixes. Never the sole carrier of a fact. Note this clears the bar the walkthrough's own `--faint` misses (3.09:1) |
| — | `.tertiaryLabelColor` | 1.88:1 / 2.26:1 | **Banned for text.** Permitted only for non-informational glyph fills that are duplicated by an adjacent word (G-4) |

`CTColor.muted` reads `@Environment(\.colorSchemeContrast)`: under Increase Contrast it returns full `.labelColor`, so the Increase-Contrast boost that a raw opacity would swallow is preserved.

#### State ramp

Defined once as `CTColor.state(_ kind: CTState) -> Color`, backed by `NSColor(name:dynamicProvider:)` so it is a single dynamic colour, not a branch at every call site:

```
dark appearance  →  the system colour, unmodified (already ≥ 4.8:1 on #1E1E1E)
light appearance →  systemColour.blended(withFraction: 0.35, of: .black)
```

| `CTState` | Base system colour | Light (blended) | Measured light / dark | Meaning, unchanged from the ratified ramp |
|---|---|---|---|---|
| `.ready` | `.systemGreen` | `#218139` | 4.93:1 / 8.24:1 | Row-level pass only. Never the tray, never a fill, never a reward |
| `.attention` | `.systemOrange` | `#A55B1A` | 5.11:1 / 7.47:1 | The single amber: something needs a look |
| `.blocked` | `.systemRed` | `#D83033` | 4.78:1 / 4.86:1 | The only red. `cli-unreadable` / honest-refusal only |
| `.actionable` | `.controlAccentColor` | accent @ 0.25 → black | ≈6.4:1 / ≈5.1:1 | "You can act on this": eyebrows, the NEW chip, `signed-out`. **Still the user's chosen accent** — the correction is a blend, not a substitution |
| `.neutral` | — | `CTColor.muted` | 5.70:1 / 7.39:1 | `setup-needed`, `waiting`, `offline`, and every shared-register row. Gray dominates by design |

Two consumption rules, both already implied by the ratified system and now made explicit because G-5 shows they were not being followed:

- **Glyphs and fills** may use the raw vivid `Color(nsColor: .systemX)`, because shape carries the state and colour is redundant (WCAG 1.4.11 exempts redundant decoration). Existing glyph call sites need no change.
- **Text** — every status word, every `Label` title, every coloured sentence — must use `CTColor.state(_:)`. This is the change at `native/user-settings.swift:607`, `:634`, `:1083`, `:1089`, `:1107`, `native/control-tower-tray.swift:1373`.

### 2.4 Type — `CTType`

Roles, sourced from the walkthrough CSS and reconciled to macOS's SF Pro metrics (macOS: `.largeTitle` 26 / `.title` 22 / `.title2` 17 / `.title3` 15 / `.headline` 13 / `.body` 13 / `.callout` 12 / `.subheadline` 11 / `.caption` 10).

| Token | Walkthrough source | Native font | Colour | Where |
|---|---|---|---|---|
| `CTType.hero` | `h1` 42/‑.035em | `.system(size: 30, weight: .semibold).tracking(-0.6)` | `ink` | Welcome and Done heroes only |
| `CTType.stepTitle` | `h3` 27/‑.025em | `.system(size: 26, weight: .semibold).tracking(-0.4)` | `ink` | Every wizard/Admin step H1 (**G-9**) |
| `CTType.lead` | `.lead` 15 muted | `.system(size: 14)` + `.lineSpacing(2)` | `muted` | The intro paragraph under a step title |
| `CTType.eyebrow` | `.eyebrow` 11/750/.07em | `.system(size: 11, weight: .semibold).tracking(0.7)` + `.textCase(.uppercase)` | `state(.actionable)` | "STEP 6 OF 9", "ONBOARDING" (**G-10**) |
| `CTType.cardTitle` | `.card-title` 11/750/.05em | `.system(size: 10, weight: .semibold).tracking(0.5)` + `.textCase(.uppercase)` | `muted` | The label above a card's rows (**G-7**) |
| `CTType.sectionTitle` | `.screen-title h2` 21 | `.system(size: 17, weight: .semibold)` | `ink` | Settings card headings, panel headings |
| `CTType.rowTitle` | `.row strong` 15/650 | `.system(size: 13, weight: .semibold)` | `ink` | The name in a status row (**G-6**) |
| `CTType.rowDetail` | `.row small` ~13 muted | `.system(size: 11)` | `muted` | The sentence under a row name (**G-3**) |
| `CTType.status` | `.status` 12/700 | `.system(size: 11, weight: .semibold)` | `state(...)` | "Ready", "Needs attention", "Now", "Next" |
| `CTType.body` | `body` 15/1.45 | `.system(size: 13)` + `.lineSpacing(2)` | `muted` | Prose inside cards and callouts |
| `CTType.bodyStrong` | `.summary` | `.system(size: 13, weight: .semibold)` | `ink` | The strong lead of a callout |
| `CTType.caption` | `.actor`, `.legend` | `.system(size: 11)` | `faint` | Actor lines, "Next actor:", counters |
| `CTType.chip` | `.chip` 10/700/.06em | `.system(size: 10, weight: .semibold).tracking(0.6)` | contextual | NEW markers, badge pills |
| `CTType.mono` | `code` 12 mono | `.system(size: 11, weight: .regular, design: .monospaced)` | `muted` | Paths, repo URLs, commands |
| `CTType.monoLabel` | `.field` 12/700 | `.system(size: 10, weight: .semibold, design: .monospaced).tracking(0.4)` | `muted` | **Credential names** in the Connect sheet — monospaced so `O`/`0` and `I`/`l` are distinguishable |
| `CTType.code` | `.code` 27/750/.09em mono | `.system(size: 24, weight: .semibold, design: .monospaced).tracking(2)` | `ink` | Device-flow `user_code`, access codes |

**Deliberate deviation from the ratified system's "semantic styles only" rule, and its justification:** §3 of `control-tower-visual-system.md` says never `.system(size:)`. That rule exists to preserve Dynamic Type. Five of the roles above (`stepTitle`, `lead`, `rowTitle`, `rowDetail`, `status`) have no semantic style at the size the walkthrough proves is right — macOS jumps 22 → 26 with nothing at 26 for a title, and 13 → 12 → 11 → 10 with the row register needing 13/11 where semantic mapping lands on 12/10. The tokens above are therefore **fixed sizes behind named roles**, which keeps one place to change them, and each is annotated with the semantic style it is nearest so a later `@ScaledMetric(relativeTo:)` pass (P3-1) can add scaling without touching a single call site. Every non-listed role keeps its semantic style.

### 2.5 Motion — `CTMotion`

| Token | Duration | Curve | Use |
|---|---|---|---|
| `CTMotion.fast` | 0.12s | `.easeOut` | Hover/press feedback, chip appearance |
| `CTMotion.normal` | 0.20s | `.easeOut` | Row state transitions, card content swaps, sheet content changes |
| `CTMotion.slow` | 0.30s | `.easeOut` | Step-to-step transitions (already at 0.2 in `native/wizard.swift:3641`) |
| `CTMotion.reduced` | 0.0s / opacity only | — | The `accessibilityReduceMotion` branch, already wired at `native/wizard.swift:3640-3641` |

`easeOut` throughout, because every animation in this app is an *arrival* — a row resolving, a step entering, a state landing. Nothing here departs, so there is no `easeIn`. There is no spring anywhere: springs imply playfulness, and this product's success state is silence.

### 2.6 Elevation

Unchanged, and worth restating because it is what keeps this native rather than web: **the app authors no shadows.** The popover floats because `NSPopover` draws its shadow; sheets and panels float because the system draws theirs; cards are flat and separated by their hairline edge alone. Adding a card shadow would be the single fastest way to make this look like an embedded webpage.

---

## 3. Components

Six small views and modifiers, all in `native/design-system.swift`. Each replaces a shape that is currently hand-built two to eight times.

### 3.1 `CTCard` — the card container (`ViewModifier` + convenience)

Replaces `sectionCard` (`native/wizard.swift:6514-6528`), `settingsCard` (`native/user-settings.swift:923-936`), `componentCard`'s chrome (`native/user-settings.swift:611-613`), and every inline `.background(controlBackgroundColor…).clipShape(RoundedRectangle…)` in the tray.

```
.ctCard()                         // default: card fill + hairline border, radius 10, padding 16
.ctCard(.well)                    // inset: well fill, NO border, radius 8, padding 16
.ctCard(.railed(.actionable))     // default + 3pt leading accent bar  (walkthrough .card.next)
.ctCard(.railed(.blocked))        // default + 3pt leading danger bar  (walkthrough .card.flag)
.ctCard(.compact)                 // default with padding 12 — the popover register
```

Anatomy, fixed: `RoundedRectangle(cornerRadius: CTRadius.card, style: .continuous)` filled `CTColor.card`, `.overlay` stroked `CTColor.cardBorder` at 1pt inset 0.5, padding `CTSpace.lg`, `.frame(maxWidth: .infinity, alignment: .leading)`. The `.railed` variants draw a 3pt-wide rounded bar at the leading edge, inside the border, in `CTColor.state(_:)` — the accent is never a fill, never a header band.

**States:** default only. Cards have no hover, no press, no focus, no selection — they are containers, not controls. If a card becomes tappable it stops being a `CTCard` and becomes a `Button` wrapping one.

### 3.2 `CTCardTitle` — the uppercase micro-label

```
CTCardTitle("Ready to use")
CTCardTitle("Still to do", trailing: .status("Nobody is named", .blocked))
CTCardTitle("Shared with your team", trailing: .note("Ready for you. Nothing to sign into."))
```

`CTType.cardTitle` leading, optional trailing element right-aligned on the same baseline (the walkthrough's `.card-title` is `display:flex; justify-content:space-between`). `.trailing` accepts a status word (`CTType.status` in the state colour) or a sentence-case note (`CTType.rowDetail`) — the two forms the walkthroughs actually use. `.accessibilityAddTraits(.isHeader)`.

Fixes G-7 everywhere, including the tray's four literal-caps strings, which become `CTCardTitle("Your copilots")` and let `.textCase` do the shouting.

### 3.3 `CTStatusRow` — the list row

The walkthrough's `.row` is a three-column grid: 25px glyph gutter, flexible content, auto trailing. Native:

```
CTStatusRow(
    glyph: .filledDot(.neutral)        // or .ring, .check(.ready), .bang(.blocked), .arrow(.actionable), .none
    title: "Infisical",
    detail: "Needs 2 credentials in your organization's secret store.",
    footnote: nil,                      // the third line, when the CLI supplies one
    trailing: .status("No action", .blocked)   // or .button("Connect…", action:) or .none
)
```

Anatomy: `HStack(alignment: .top, spacing: CTSpace.md)`; glyph in a fixed 20pt-wide gutter, top-aligned to the first text baseline; `VStack(alignment: .leading, spacing: CTSpace.hair)` of `CTType.rowTitle` / `CTType.rowDetail` / `CTType.caption`; `Spacer(minLength: CTSpace.md)`; trailing. Vertical padding `CTSpace.rowV`. Consecutive rows separate with `Divider()` (which is `CTColor.hairline`), never with a gap — the walkthrough's `.row + .row {border-top}` is what makes a card read as a list rather than as loose paragraphs.

**States, all seven:** default; `hover` — none for a read-only row (the walkthrough's shared rows are deliberately inert, and rule 07 of the floor says a shared row carries no button); `focus` — only when `trailing` is a button, and then it is the system ring on the button, never on the row; `active`/`disabled` — delegated to the trailing control; `loading` — trailing becomes `CTNamedWaitSpinner` (the existing `native/wizard.swift:341` component, unchanged) plus a present-tense detail line; `error` — the row keeps its shape and the state moves to `.attention` or `.blocked` with a CLI-authored sentence in `detail`; `empty` — the row does not render, and its card renders the group's own honest sentence instead.

One hard rule carried from the walkthrough floor (rule 04): **`trailing: .button` is legal only when the person reading the row can actually complete the action.** A row whose only action belongs to someone else takes `.status` and a `CTCalloutNote` naming that person.

### 3.4 `CTCalloutNote` — glyph gutter + strong lead + body

The walkthrough's `.callout`, which is the shape the honesty voice lives in.

```
CTCalloutNote(
    kind: .info,                     // .info | .ready | .attention | .blocked
    lead: "Your access to your team's shared connections was turned off.",
    body: ["Anything you saved on this Mac is still yours, and nothing was removed.",
           "If that's a surprise, ask whoever looks after Accounting."],
    actor: "Next actor: whoever looks after Accounting."   // optional
)
```

Anatomy: `HStack(alignment: .top, spacing: CTSpace.md)`, a 24pt glyph gutter carrying the state symbol in the raw vivid system colour (shape-first, redundant colour), then `VStack(spacing: CTSpace.xs)` of `CTType.bodyStrong` lead + `CTType.body` paragraphs. `actor`, when present, sits under a hairline `Divider()` with `CTSpace.sm` above, in `CTType.caption` — the walkthrough's `.actor` rule exactly. Usually wrapped in `.ctCard(.well)`.

**No `CTCalloutNote` ever carries a button.** If a next step exists it belongs to the surrounding card's action row, so the callout can never look like a control.

### 3.5 `CTDecisionBlock` — the two-column fact list

The walkthrough's `.decision`: a fixed label column and an explanation, hairline-separated. This is what the app should use wherever it currently renders "label: value" as a paragraph.

```
CTDecisionBlock([
    .init("Store type",    "Infisical"),
    .init("Store address", "https://secrets.enac.example", style: .mono),
    .init("Which teams",   "Accounting, Sales"),
])
```

Anatomy: rows of `HStack(alignment: .firstTextBaseline, spacing: CTSpace.md)` with the label in `CTType.rowDetail`/`muted` at a fixed `120pt` width (`.frame(width: 120, alignment: .leading)`), value in `CTType.body`/`ink` or `CTType.mono`, `CTSpace.sm` vertical padding, `Divider()` between. At the narrowest supported window and at accessibility text sizes it collapses to stacked label-over-value — checked with `@Environment(\.dynamicTypeSize)`, matching the walkthrough's own `@media(max-width:680px)` collapse.

### 3.6 `CTChip` — the inline marker

`CTType.chip` in a capsule stroked `CTColor.cardBorder`, `CTSpace.xs`/`CTSpace.sm` padding. `.new` variant strokes and tints with `CTColor.state(.actionable)`. Replaces the two hand-built chips at `native/wizard.swift:5121` and `native/wizard.swift:6586`.

---

## 4. Per-surface application map

**P1 is the whole perceived-quality lift and is a pure styling pass**: one new file, plus substitutions inside existing view bodies. No `View` is split, merged, renamed, or re-parented; no `@State`, model, or CLI call changes. `StepShell`'s public signature is explicitly preserved (its doc comment at `native/wizard.swift:3394-3399` warns that `admin.swift` and `admin-support.swift` are heavy consumers — nothing in P1 touches that signature).

### P1 — do these

| # | Surface | Before → After | Files |
|---|---|---|---|
| **P1-1** | Foundation | No token layer exists; 13 padding values, 6 radii, 3 phantom card weights → one `native/design-system.swift` holding `CTSpace`/`CTRadius`/`CTColor`/`CTType`/`CTMotion` and the six components. Added to both build source lists. | new file; `scripts/build-user.command:24-30`; `scripts/build-admin.command` |
| **P1-2** | **Every card, everywhere** | Invisible edgeless fill identical to the page → `.ctCard()`: hairline border + 3–5% tint. This one substitution is the largest single change in perceived quality, because it makes structure that is already in the code visible for the first time. | `wizard.swift:6514`; `user-settings.swift:923`, `:611`, `:557`, `:891`, `:908`; `control-tower-tray.swift:1927`, `:1944`, `:2117`, `:2196`, `:2235`, `:2349` |
| **P1-3** | **Row typography ramp** | `.callout.semibold` (12) + `.caption` (10) secondary + `.caption` (10) tertiary → `CTType.rowTitle` (13) + `CTType.rowDetail` (11 muted) + `CTType.caption` (11 faint). Kills the 1.88:1 tertiary sentences and the 3.95:1 caption sentences in one pass. | `wizard.swift:4610-4684`, `:4696-4733`, `:4738-4751`, `:6531-6543`; `user-settings.swift:617-640`, `:746-767`, `:773-804`, `:808-821` |
| **P1-4** | **Wizard step chrome** | `StepShell` eyebrow `.caption` raw-accent untracked; title `.title` (22); intro `.body` (13) → `CTType.eyebrow` (tracked, contrast-corrected accent), `CTType.stepTitle` (26, tracked), `CTType.lead` (14, muted, `lineSpacing 2`). Content inset moves to `CTSpace.pane`/`CTSpace.paneTop`; the `maxWidth: 600` column is kept. **Four lines in one struct, and it changes every step of the wizard and every Admin pane at once.** | `wizard.swift:3449-3474` |
| **P1-5** | **State colour on text** | `.systemGreen` (2.22:1) / `.systemOrange` (2.31:1) as text colour → `CTColor.state(.ready/.attention/.blocked)`. Glyph call sites unchanged. | `user-settings.swift:607`, `:634`, `:1083`, `:1089`, `:1107`; `control-tower-tray.swift:1373`; `wizard.swift` status words |
| **P1-6** | **Section labels** | Three treatments, four literal-caps strings → `CTCardTitle`, sentence-case source strings, `.textCase(.uppercase)` + tracking, `.isHeader`. | `wizard.swift:6516-6521`; `user-settings.swift:928-929`; `control-tower-tray.swift:1549`, `:1570`, `:1601`, `:1608` |
| **P1-7** | **Connections screens** (wizard step 6 + Settings "Your connections") | Two hand-built row geometries with different paddings → `CTStatusRow` in `.ctCard()` under `CTCardTitle`. The `needs-connect` row keeps its `Connect…` button; the `no-store` group keeps having none. Ready/needs-connect/no-store visually rank for the first time. | `wizard.swift:4601-4805`; `user-settings.swift:642-821` |
| **P1-8** | **Connect sheet** | Section 5 below. | `user-settings.swift:997-1148` |
| **P1-9** | **Tray popover** | Region labels via `CTCardTitle`; component rows via `CTStatusRow`; the three phantom card weights collapse to `.ctCard(.compact)` and `.ctCard(.well)`; popover material and 360pt width unchanged. | `control-tower-tray.swift:1445-1622`, `:1900-2360` |
| **P1-10** | **Settings header** | `.largeTitle` "Your setup" + `.title2` + `.body` secondary → `CTType.hero` + `CTType.sectionTitle` + `CTType.lead`; cards get `CTCardTitle` instead of the `.title3` title-case heading. | `user-settings.swift:486-532`, `:923-936` |

### P2 — do these next

| # | Surface | Change |
|---|---|---|
| P2-1 | Holding views (`h1View`…`h7View`, `honestIncompleteView`) | Adopt `CTCalloutNote` for the seven honest terminals and `CTDecisionBlock` for "what this means" fact lists, replacing eight hand-built geometries (G-11) |
| P2-2 | Verify / Done step | `CTCardTitle` + `CTStatusRow` for the "Ready now" card; delete any residual completion decoration (floor rule 11) |
| P2-3 | Step 8 "Set up" progress | `CTStatusRow` with `.loading` trailing for the in-flight part; the phase is named, never timed |
| P2-4 | Projects triage rows and drill-in | `CTStatusRow` + `.ctCard()`; the count numeral keeps `.title3.semibold` as a deliberate scale break |
| P2-5 | `CTChip` adoption | The two hand-built chips, plus NEW markers wherever the copy deck introduces one |
| P2-6 | Sheets (`InstallHelperSheet`, `GrantPermissionSheet`, `GrantFallbackSheet`, `OrgSignInIDSheet`, `OrgHelpSheet`) | Shared sheet chrome: `CTSpace.section` padding, `CTType.sectionTitle` + `CTType.lead`, `.ctCard(.well)` for code blocks, `CTType.code` for codes |
| P2-7 | Admin surfaces (`admin.swift`, `admin-support.swift`) | Same substitutions; they inherit P1-4 free through `StepShell`, so this is cards and rows only |
| P2-8 | Row transition motion | `CTMotion.normal` cross-fade when a `CTStatusRow` changes state, `CTMotion.reduced` under Reduce Motion |

### P3 — defer

| # | Change | Why deferred |
|---|---|---|
| P3-1 | `@ScaledMetric(relativeTo:)` on every fixed size in `CTType` | Mechanical once the tokens exist; adds no visual lift; touches only `design-system.swift` |
| P3-2 | `CTDecisionBlock` responsive collapse tuning at accessibility sizes | Needs real Dynamic Type testing on hardware |
| P3-3 | Card hover affordance | Currently correct to have none; revisit only if a card becomes tappable |
| P3-4 | Popover width/height re-derivation | The ratified 360pt is right; revisit after P1-9 lands and regions are re-measured |
| P3-5 | Brand mark in the wizard sidebar | Twice tried and twice rejected at 16pt (`wizard.swift:3511-3518`) — needs a purpose-drawn small mark, which is an asset job, not a styling pass |

---

## 5. The Connect sheet

The sheet exists (`native/user-settings.swift:997-1148`, presented from `wizard.swift:3685` and `user-settings.swift:473`) and its behaviour is right: values live in `@State` only while the sheet is open, go to the CLI on stdin once, are cleared unconditionally after, and the CLI — never the app — decides whether the connection took. **Nothing in this section changes any of that.** This is its visual anatomy on the token system, plus two honesty corrections.

### 5.1 Frame

Width **520pt** fixed (down from 560 — the field labels are monospaced and short, and a narrower sheet reads more like an instrument and less like a form). Height `380 + 64 × fields.count`, clamped to 560, replacing the current binary `fields.count > 2 ? 560 : 470`. Padding `CTSpace.section` (24) on all sides — the current 28 is off-grid. Vertical rhythm `CTSpace.xl` between the four blocks (header, promise, fields, outcome), `CTSpace.section` above the footer.

### 5.2 Anatomy, top to bottom

**Header.** Title `Connect {Service}` in `CTType.sectionTitle` (17 semibold), `CTColor.ink`. Directly under it, the CLI's own `row.description` in `CTType.lead`, `CTColor.muted`, `CTSpace.hair` gap. No eyebrow: a sheet has no step number, and adding one would imply this is part of a sequence it can fail out of.

**The promise paragraph.** One block, `CTType.body`, `CTColor.muted`, `.lineSpacing(2)`: *"Whoever set up your organization's shared store gives you these. Control Tower hands them straight to this Mac's keychain — they are never shown again, never written into a project, and never sent anywhere."* This is the sentence that makes the ask survivable, so it sits above the fields, not below them, and it is never truncated (`.fixedSize(horizontal: false, vertical: true)`).

**The field group.** One `.ctCard(.well)` — recessed, radius 8, no border — containing `fields` (which is `row.missing`, in the CLI's own order, never re-sorted, never filtered) with `CTSpace.lg` between entries.

Each entry is label-over-field:

- **Label = the credential name, verbatim, as the field's own label.** `CTType.monoLabel` (10pt semibold monospaced, tracked 0.4), `CTColor.muted`. Monospaced because a person is transcribing this from a message or a password manager and must be able to tell `INFISICAL_CLIENT_ID` from `INFISICAL_CLIENT_1D`. **Never uppercase-transformed** — the name is data from the CLI, and the app must not restyle a literal it will later send back.
- **Field:** `SecureField("", text:)` with `.textFieldStyle(.roundedBorder)` — native rounding, native focus ring, no restyling. `CTSpace.xs` below the label. `.disabled(working)`. `.accessibilityLabel(name)` and no `accessibilityValue`, so the value is never spoken, never in a screenshot, never in an a11y dump.
- **Autofocus:** `@FocusState` on the first field, set in `.onAppear`. Tab moves between fields in CLI order; Return submits when `canSubmit`.
- **Optional helper text** under a field, `CTType.caption`/`CTColor.faint`, rendered **only** if the CLI supplied one for that name. The app never composes a hint about a credential it does not understand (invariant #1).

**Outcome region.** Reserves no space when empty; appears with `CTMotion.normal` (opacity only under Reduce Motion). See 5.4.

**Footer.** `HStack(spacing: CTSpace.md)`: while working, an inline `ProgressView().controlSize(.small)` plus *"Saving these to your keychain…"* in `CTType.body`/`CTColor.muted` on the leading side; then `Spacer()`; then `Cancel` (`.bordered`, disabled while working) and the primary (`.borderedProminent`, `.keyboardShortcut(.defaultAction)`, disabled unless every field is non-empty and no call is in flight). Primary label is `Connect`, becoming `Try again` once an outcome exists — unchanged, and correct.

### 5.3 The store row's state transition on success — **correction to what ships**

Today the sheet renders a green `checkmark.circle` "Connected." (`user-settings.swift:1081-1083`). That is the celebration the copy deck's hard rule 6 and the walkthrough floor's rule 11 both forbid, and it is the wrong place for the receipt besides: the sheet is about to disappear.

**Specified behaviour:** on `.connected`, the sheet posts no success state at all. It calls `onConnected(fresh)` immediately, the caller re-reads the whole roster from the CLI (already the behaviour at `wizard.swift:3691` and `user-settings.swift:478` — a second, independent read is what proves screen and machine agree), and the sheet dismisses.

**The receipt is the row behind it**, and it is the one place the success is allowed to be visible:

| | Before | After |
|---|---|---|
| Glyph | `circle` hollow ring, `CTColor.muted` | `circle.fill` 8pt dot, `CTColor.state(.neutral)` — the same quiet dot the GitHub row already uses, **not** a green check |
| Title | `Infisical` | unchanged |
| Detail | "Needs 2 credentials in your organization's secret store." | the CLI's re-checked `description` |
| Third line | the `needs-connect` detail | gone |
| Trailing | `Connect…` button | `Ready` in `CTType.status`, `CTColor.state(.neutral)` |
| Card group | under `CTCardTitle("Available to connect")` | moves under `CTCardTitle("Ready to use")`; if it was the last row, the "Available to connect" card **disappears entirely** |

Transition: `CTMotion.normal` cross-fade on the row, driven by the re-read, not by a local optimistic edit. Under Reduce Motion the roster simply re-renders. The disappearing heading is the strongest part of this — it is exactly the walkthrough's *"the 'Available to your team' heading is gone, because nothing under it is pending any more."*

### 5.4 Error presentation, per the honesty floor

Three outcomes, all CLI-authored, none of them a dead end, none of them red. **Red is reserved for `cli-unreadable`**; a credential that did not take is an `.attention`, because the person can act on it.

| Outcome | Glyph + colour | Content | Next actor |
|---|---|---|---|
| `.notConnected(title, details)` | `exclamationmark.triangle`, `CTColor.state(.attention)` | `title` in `CTType.bodyStrong`; each `detail` on its own line in `CTType.body`/`muted`; then the fixed floor line *"Nothing else on this Mac was changed. Check the values with whoever gave them to you, then try again."* in `CTType.caption`/**`CTColor.faint`** — promoted out of `.tertiaryLabelColor` (G-4) | The person, with a named human to check against. Primary becomes `Try again` |
| `.unreadable(sentence)` | `exclamationmark.triangle`, `CTColor.state(.attention)` | `sentence` in `CTType.bodyStrong`; then *"You can close this and try again whenever you want."* in `CTType.caption`/`CTColor.faint` | Control Tower itself, and it says so. No retry loop is implied |
| store unreachable mid-submit | `cloud` / `clock`, `CTColor.state(.neutral)` | The same outage sentence the connections screen uses. Never a second dialect for the same fact (floor rule 09) | Control Tower keeps checking; no button |

Rendered inside a `CTCalloutNote(kind: .attention, …)` wrapped in `.ctCard(.well)`, so the failure has the same shape as every other honest degrade in the product rather than an inline-`Label` shape unique to this sheet.

Three rules the sheet must keep passing, restated because they are visual as well as behavioural:

1. **No raw error text on this surface, ever.** Every string above comes from `ConnectRender`, which reads the CLI's verdict. If the CLI supplies nothing renderable, the app shows the `.unreadable` sentence — never a stderr dump (floor rule 01).
2. **No value on screen, in any form** — not masked, not the first four characters, not in a tooltip, not in an accessibility label (floor rule 03).
3. **Never a dead end.** Every terminal state above names an actor or offers a self-retry. `Cancel` is always live except during the call itself.

---

## 6. Accessibility

**Contrast targets, and the measured evidence they are built on.** Text ≥ **4.5:1**; UI components and focus indicators ≥ **3:1**; decorative marks that duplicate an adjacent word are exempt (WCAG 1.4.11). Verified in this pass:

| Token | Light | Dark | Verdict |
|---|---|---|---|
| `CTColor.ink` on page | 14.94:1 | 12.23:1 | pass |
| `CTColor.muted` on page | 5.74:1 | 6.77:1 | pass — replaces `.secondaryLabelColor` for load-bearing text |
| `CTColor.faint` on page | 4.95:1 | 6.07:1 | pass |
| `CTColor.state(.ready)` text | 4.93:1 | 8.24:1 | pass — raw `.systemGreen` was 2.22:1 |
| `CTColor.state(.attention)` text | 5.11:1 | 7.47:1 | pass — raw `.systemOrange` was 2.31:1 |
| `CTColor.state(.blocked)` text | 4.78:1 | 4.86:1 | pass — raw `.systemRed` was 3.57:1 |
| `CTColor.state(.actionable)` text | ≈6.4:1 | ≈5.1:1 | pass — raw accent was 4.02:1 |
| `.secondaryLabelColor` | 3.95:1 | 5.89:1 | **fails light** — permitted only at ≥13pt supplementary |
| `.tertiaryLabelColor` | 1.88:1 | 2.26:1 | **banned for text** |
| `CTColor.cardBorder` vs page | ≈1.25:1 | ≈1.34:1 | decorative boundary, exempt — a card is identified by its content and its title, never by its edge alone |

**Increase Contrast.** `CTColor.muted` and `CTColor.faint` read `@Environment(\.colorSchemeContrast)` and return full `.labelColor` when `.increased`, so the system setting still does something. `CTColor.cardBorder` is `.separatorColor`, which the system already strengthens.

**Focus rings.** Never restyled, never suppressed, never recoloured — the system ring on the system control, which is the nativeness contract and the a11y contract in the same decision. `CTCard` and `CTStatusRow` are not focusable; only their trailing controls are. Tab order follows visual order, which follows the CLI's own row order.

**Touch/click targets.** All interactive controls keep native heights with a 44pt effective hit area. Read-only rows deliberately get **no** hit area: the absence of the target is how a person learns a shared row is not theirs to operate (floor rule 07), and giving an inert row a hover or a pointer cursor would undo that.

**Colour independence.** Unchanged and re-verified by construction: every state is carried by a shape from the ratified 12-badge vocabulary **and** by a word (`Ready` / `Needs attention` / `No action` / `Now` / `Next`) before colour is applied. `CTStatusRow` makes this structural — a state cannot be set without supplying both.

**VoiceOver.** `CTStatusRow` combines children into one element reading *"{title}, {status word}, {detail}"*. `CTCardTitle` carries `.isHeader`. `CTCalloutNote`'s glyph is `.accessibilityHidden(true)` because the lead sentence already says the state. Credential fields are labelled by name with no value exposed. The existing per-site labels (`wizard.swift:4630`, `:4683`, `:4724`; `user-settings.swift:766`, `:795`) are preserved verbatim by the substitution — `CTStatusRow` takes an optional `accessibilityLabel` override for exactly this.

**Reduced motion.** `CTMotion.reduced` is opacity-only at zero duration. It applies to the step transition (already wired, `wizard.swift:3640-3641`), the connection-row state flip, and the Connect sheet's outcome appearance. No motion in this app conveys information that its absence would remove.

**Dynamic Type.** P1 keeps the current behaviour; every fixed size is behind a named token so P3-1 can add `@ScaledMetric(relativeTo:)` in one file. All text keeps `.fixedSize(horizontal: false, vertical: true)` so it wraps rather than clips, and `CTDecisionBlock` collapses to stacked at accessibility sizes.

---

## 7. Implementation notes

- **One new file.** `native/design-system.swift`. It must be added to the explicit source list at `scripts/build-user.command:24-30` and to the equivalent list in `scripts/build-admin.command` — those lists are deliberate (they exist so the user build can never pull in the Admin-only sources), so a glob will not pick it up.
- **`StepShell`'s signature is untouched.** P1-4 changes only the fonts, colours, and paddings inside its `body` (`wizard.swift:3440-3498`). Its `init` and `.headerTint(_:)` stay exactly as documented at `wizard.swift:3394-3399`, so `admin.swift` and `admin-support.swift` inherit the refresh with zero edits.
- **`ConnectSheet` stays where it is** — shared by both callers on purpose (`user-settings.swift:967-996`). P1-8 restyles its body; the credential-handling rules in that doc comment are load-bearing and unchanged.
- **Substitution, not rewrite.** Every P1 item replaces literals inside an existing `body`. If an item starts requiring a new `@State`, a new view file, or a changed initialiser, it has left P1 and should be re-scoped.
- **Verification.** `scripts/tests/smoke-scenarios.sh` and `scripts/tests/test_walkthrough_05_08_acceptance.sh` already exercise these surfaces; the visual-test build flag `CT_VISUAL_TEST_BUILD` (`control-tower-tray.swift:1455-1460`) gives a deterministic popover for screenshot diffing. A contrast assertion — every text token ≥ 4.5:1 under both appearances — belongs in the suite alongside them, because G-3/G-4/G-5 were all silent regressions that no existing test could have caught.
- **A caution about the tray.** `native/control-tower-tray.swift` may have concurrent work in flight from another session. P1-9 is the most collision-prone item and should land last, after P1-1 exists and the other surfaces have proven the tokens.

---

## Sources

- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/15-connect-experience-uxd-walkthrough.html` — card/row/callout/decision anatomy, the eleven floor rules, the Connect and access-request sheets
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/16-self-service-provisioning-uxd-walkthrough.html` — the shipped-today Connect screen, the bridge's own terms
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/05-truthful-setup-recovery-uxd-walkthrough.html` — the token source (`:root` custom properties, both appearances)
- `docs/03-design/control-tower-visual-system.md` — the ratified system this extends: §2 colour roles, §3 type registers, §4 badge vocabulary, §5 spacing/radii/materials, §9 accessibility
- `docs/03-design/control-tower-copy-deck.md` — hard rule 6 (no celebration), §1.3 section labels, §1.6 integration rows
- `native/wizard.swift`, `native/user-settings.swift`, `native/control-tower-tray.swift` — read-only, cited by line as evidence and as substitution targets
- Colour measurements taken on this machine (Darwin 25.5) by rasterizing `NSColor` under `.aqua` and `.darkAqua` via `NSAppearance.performAsCurrentDrawingAppearance`, then computing WCAG 2.1 relative-luminance ratios
