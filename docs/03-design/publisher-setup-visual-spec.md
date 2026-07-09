# Publisher Setup: Visual & Interaction Design Spec

Implementer-ready redesign spec for `scripts/publisher_setup.swift` → **Publisher Setup.app**.
Target: a calm, native, first-party-feeling macOS SwiftUI assistant that walks a first-time
publisher from "I have nothing" to "a signed, notarized, stapled `.app` + `.dmg`, handed to Admin."

- **Mode:** Controlled. This is macOS. We do **not** invent a design system; we commit to the
  Apple platform vocabulary (system semantic colors, `NSVisualEffectView` materials, SF fonts, SF
  Symbols, standard controls). The craft is in restraint, spacing, hierarchy, and never-dead-end flow.
- **Aesthetic direction (named):** **"Setup Assistant Calm"**: the visual language of Apple's own
  first-run assistants (Migration Assistant, Setup Assistant, Xcode account onboarding): a persistent
  navigation rail that shows the whole journey, a single focused content pane, one clear primary
  action per screen, and generous quiet space that lowers the anxiety of someone holding signing
  authority they don't fully understand.
- **Rejected directions & why:**
  - *"Utilitarian form"* (the current build: stacked gray cards, one giant scroll): communicates
    "internal tool," gives no sense of place or progress, and dead-ends the user in walls of helper
    text. Rejected: fails goals 1 and 2.
  - *"Marketing onboarding"* (full-bleed hero art, illustrations, big gradients): fights the platform,
    reads as a web app, and over-promises for a technical utility. Rejected: violates HIG restraint,
    triggers AI-slop detectors.

Grounded in Apple's Human Interface Guidelines (Onboarding, Materials, Sidebars, SF Symbols,
Typography); see Sources at the end.

---

## 0. Ground Truth: current flow being redesigned

The existing `SetupPhase` enum drives a single switch over full-window views:
`prerequisites → guide(x4) → form → success → publishing → published → failure`.
It is a flat form with gray `controlBackgroundColor` cards, hardcoded point sizes
(`.system(size: 28/24/14/13/12/11)`), 28pt padding, 8pt radii, and no sense of progress or place.

This spec keeps the underlying state machine and CLI/`Process` logic **unchanged** and re-skins +
re-structures the presentation, while adding four audit-required screens: **Welcome**, **Cert-Trust
Verify**, a persistent **Roadmap**, and a structured **Handoff** block on success.

---

## 1. Design Language

### 1.1 Window chrome & materials

- **Window style:** standard titled window, unified toolbar-less title bar. Keep traffic lights
  top-left (HIG: never hide/move them). Title: "Publisher Setup".
- **Structure:** `NavigationSplitView`: a fixed **sidebar (roadmap)** + **detail content pane**.
  This is the HIG-blessed macOS pattern for multi-section apps and reads instantly as native.
  Sidebar is **non-collapsible** here (it is the progress map, not optional nav); set
  `.navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)` and remove the collapse control
  by not offering a toolbar toggle.
- **Sidebar material:** the sidebar automatically renders on the system **sidebar material**
  (`NSVisualEffectView.Material.sidebar`, vibrancy on). Do **not** paint it a flat color; let the
  material show. This alone is 80% of the "Apple made this" read.
- **Content pane background:** `Color(nsColor: .windowBackgroundColor)`. Individual grouped content
  uses `.controlBackgroundColor` surfaces sparingly (see §4).
- **Overlay material:** the long build screen's log panel and any transient confirmation use
  `.regularMaterial` only where content floats; inline content stays opaque.

### 1.2 Window sizing

| Property | Value | Rationale |
|---|---|---|
| Min size | **820 × 620** | Fits sidebar (260) + a comfortable 520 content column at min. Down from the current 860×900 which forces scrolling on laptops. |
| Ideal / default | **960 × 720** | Roomy, single-screen for most steps; centers on 13" displays. |
| Max | unbounded, but content column caps at **640pt** | Long-line measure control (see typography). |
| Content column | centered, `maxWidth: 640` | Keeps reading measure at ~70–90 chars; prevents the current edge-to-edge sprawl. |
| Window resizable | yes | HIG expectation; layout is fluid within the caps. |

### 1.3 Color system (system semantic only: light + dark automatic)

Never hardcode RGB. Every color below is a system semantic color that adapts to light/dark and
accessibility contrast settings automatically.

| Token (spec name) | SwiftUI / NSColor | Usage | Contrast |
|---|---|---|---|
| `label` | `.labelColor` | Primary text: titles, values | AA+ on all system backgrounds |
| `secondaryLabel` | `.secondaryLabelColor` | Body copy, descriptions | AA (system-guaranteed) |
| `tertiaryLabel` | `.tertiaryLabelColor` | Captions, hints | Use only ≥11pt |
| `windowBackground` | `.windowBackgroundColor` | Content pane base | N/A |
| `contentSurface` | `.controlBackgroundColor` | Grouped cards / inset panels | N/A |
| `fieldSurface` | `.textBackgroundColor` | Text areas, log, code blocks | N/A |
| `separator` | `.separatorColor` | Hairline dividers, step connectors | 3:1 not required (decorative) |
| `accent` | `.controlAccentColor` (system, user-tinted) | Primary buttons, active roadmap step, focus | Respect user's accent |
| `tintBlue` | `.systemBlue` | Eyebrow labels, informational glyphs, links | AA on surfaces |
| `success` | `.systemGreen` | Verified/complete states, done checks | Pair with glyph, never color-only |
| `warning` | `.systemOrange` | "Needs attention," untrusted-but-fixable | Pair with glyph |
| `danger` | `.systemRed` | Failure states, destructive/error | Pair with glyph |

**Rule:** status is **never** encoded by color alone: always color **+ SF Symbol + text label**
(accessibility & the color-blind publisher). The current build already leans on green checks; keep
the glyph, add the label.

### 1.4 Typography scale (map to SF Text/Display via semantic `Font`)

**Stop hardcoding `size:`.** Use semantic `Font` styles so Dynamic Type and the SF optical sizing
work. Mapping (SwiftUI style → role → weight):

| Role | SwiftUI Font | Weight | Where |
|---|---|---|---|
| Screen title | `.largeTitle` | `.semibold` | Welcome hero title only |
| Step title | `.title` | `.semibold` | Every step's H1 (replaces `size:28`) |
| Section header | `.title3` | `.semibold` | Card/section titles (replaces `size:14 semibold`) |
| Eyebrow / kicker | `.caption` | `.semibold`, `.textCase(.uppercase)`, `tintBlue` | "PUBLISHER PREREQUISITE 3 OF 4" |
| Body | `.body` | `.regular` | Descriptions, "why this matters" |
| Emphasis body | `.body` | `.medium` | Checklist item titles |
| Callout | `.callout` | `.regular` | Helper text under fields |
| Caption | `.caption` | `.regular` | Field captions, hints |
| Mono value | `.body`, `.monospaced()` | `.regular`/`.semibold` | Team ID, paths, log |

Line spacing: rely on default leading; for multi-line body add `.lineSpacing(2)`. Titles get
`.fixedSize(horizontal: false, vertical: true)` to wrap, never truncate.

### 1.5 Spacing scale (8pt grid)

Adopt a strict scale; delete ad-hoc `18/14/28`:

`4 (hairline) · 8 (tight) · 12 (compact) · 16 (default) · 24 (section) · 32 (pane inset) · 48 (hero)`.

- Content pane inset: **32** horizontal, **24** top.
- Between sections: **24**.
- Inside a card: **16** padding, **12** between rows.
- Field label↔control: **8**.
- Sidebar row vertical padding: **8**, horizontal **12**.

### 1.6 Corner radii

| Radius | Where | Character |
|---|---|---|
| **10** (`.continuous`) | Cards, panels, log block, code block | Matches macOS grouped-content rounding; friendly-but-serious |
| **6** (`.continuous`) | Inline chips, roadmap active pill | Subtle |
| system default | Buttons, text fields | **Do not restyle**: native `.roundedBorder`/`.bordered` rounding is the signal of nativeness |
| **50%** | Roadmap step status glyph background circle | Standard status dot |

Never restyle button/textfield corners; using the platform default IS the intentional choice here.

### 1.7 Elevation

Assistants are flat. Only two elevations exist:

| Level | Shadow | Use |
|---|---|---|
| 0 (flat) | none | All inline cards, sidebar, content: they sit on the ground plane |
| 1 | `0 1px 3px rgba(0,0,0,0.12)` (system default via material) | Only if a confirmation popover/sheet appears |

No decorative shadows on cards. Depth comes from the **sidebar material vibrancy** vs. opaque content,
not drop shadows. This is the honest macOS spatial model.

### 1.8 Iconography: SF Symbols (specific per role)

Use SF Symbols, `.hierarchical` rendering by default, `.palette` for status where a second tone helps.
Symbol point size tracks the adjacent text style (`.imageScale(.large)` next to titles).

| Meaning | Symbol | Rendering |
|---|---|---|
| Publisher / identity | `person.badge.key` | hierarchical |
| Welcome / release authority | `checkmark.seal` | hierarchical, tintBlue |
| Prerequisites checklist | `checklist` | hierarchical |
| Membership | `person.crop.circle.badge.checkmark` | hierarchical |
| Certificate | `lock.doc` / `signature` | hierarchical |
| Trust chain (G2 intermediate) | `link.badge.plus` | hierarchical |
| App-specific password | `key.horizontal` | hierarchical |
| Signing identity detect | `magnifyingglass` (detecting) → `checkmark.seal.fill` (found) | palette |
| Cert-trust verify OK | `checkmark.shield.fill` | palette (green + white) |
| Cert-trust untrusted | `exclamationmark.shield.fill` | palette (orange + white) |
| Cert-trust no key | `xmark.shield.fill` | palette (red + white) |
| Team ID | `number` | hierarchical |
| Notary | `paperplane` | hierarchical |
| Release config / env | `doc.badge.gearshape` | hierarchical |
| Building (in progress) | `hammer` + `ProgressView` | N/A |
| Success / handoff ready | `shippingbox.fill` / `checkmark.circle.fill` | palette green |
| Failure | `exclamationmark.triangle.fill` | palette red |
| Copy | `doc.on.doc` | monochrome |
| Open web console | `arrow.up.forward.app` | monochrome |
| Roadmap step: done | `checkmark.circle.fill` | success |
| Roadmap step: current | `circle.inset.filled` | accent |
| Roadmap step: upcoming | `circle` | tertiaryLabel |

---

## 2. Layout System

### 2.1 Overall chrome: sidebar roadmap + content pane

```
┌───────────────────────── Publisher Setup ──────────────────────────┐
│●●●                                                                  │
├──────────────────┬──────────────────────────────────────────────── │
│  SIDEBAR (260)   │  CONTENT PANE (fluid, content col max 640)       │
│  [material]      │  [windowBackground]                              │
│                  │                                                  │
│  Publisher Setup │   EYEBROW · STEP 3 OF 7                          │
│  (app label +    │   Step Title (.title, semibold)                 │
│   person.badge   │   Body intro paragraph (.body, secondaryLabel)  │
│   .key glyph)    │                                                  │
│                  │   ┌── card / component region ──────────────┐   │
│  ROADMAP:        │   │  ...focused content for this step...     │   │
│  ✓ Welcome       │   └──────────────────────────────────────────┘  │
│  ✓ Prerequisites │                                                  │
│  ◉ Signing ID    │                                                  │
│  ○ Trust Verify  │                                                  │
│  ○ Notary        │  ───────────── footer divider ───────────────   │
│  ○ Release Config│  [Secondary]           status text    [Primary] │
│  ○ Build         │                                                  │
│  ○ Handoff       │                                                  │
└──────────────────┴──────────────────────────────────────────────── ┘
```

- **Sidebar = the persistent roadmap.** Always visible, always shows all seven stages with
  done/current/upcoming state. It answers "where am I / what's left" at every moment: the #1 audit
  gap. Rows are **not freely clickable forward** (can't skip signing); completed rows *are* tappable
  to review (routes back read-only). Current row: accent pill (radius 6) behind it + `circle.inset.filled`.
- **Content pane = one focused step.** Fixed anatomy every screen: eyebrow → title → intro → content
  region → footer action bar. This repetition is the calm.
- **Footer action bar** is pinned to the pane bottom (not scrolled): `Divider()` then an `HStack` with
  secondary action(s) leading, an ephemeral status/`copiedMessage` label center-left, `Spacer()`,
  **primary action trailing** (HIG: default/confirming button bottom-trailing). Replaces the current
  left-aligned button rows.

### 2.2 Roadmap stages (7) mapped to `SetupPhase`

| # | Roadmap stage | Backing phase(s) | Symbol |
|---|---|---|---|
| 1 | Welcome | *(new)* `.welcome` | `checkmark.seal` |
| 2 | Prerequisites | `.prerequisites`, `.guide(x)` | `checklist` |
| 3 | Signing Identity | *(new)* `.identity` (split from form) | `person.badge.key` |
| 4 | Trust Verify | *(new)* `.trustVerify` | `checkmark.shield` |
| 5 | Notary & Config | `.form` (notary + env sections) | `paperplane` |
| 6 | Build | `.publishing` | `hammer` |
| 7 | Handoff | `.success`→`.published` (merged outcome) | `shippingbox` |
| N/A | Failure | `.failure` | overlay/inline banner, does not add a stage |

Implementation note: add a `RoadmapStage` enum + a computed `currentStage(for: phase)`; the sidebar
derives done/current/upcoming from stage index vs. current. Keep the existing `SetupPhase` engine.

---

## 3. Screen-by-Screen Spec (every state)

Each screen uses the §2.1 anatomy. "Primary" = bottom-trailing default button; "Secondary" = leading.

### 3.1 Welcome / Orientation (NEW), stage 1

- **Purpose:** Ground a stranger. Explain what "publisher" means, that they hold **release-signing
  authority only** (not fleet/admin, not user data), and preview the roadmap. Calm, confidence-building.
- **Layout:** centered, no card, a hero. `checkmark.seal` glyph (48pt, tintBlue, hierarchical) →
  `.largeTitle` title "You're set up to publish a release." → one `.body` paragraph in plain language
  → a compact 3-item "what you'll do / what you won't touch" list using `.callout`:
  - `checkmark.circle` You'll produce one signed, notarized app + disk image.
  - `checkmark.circle` This Mac already has (or will get) the Apple credentials.
  - `xmark.circle` (tertiary) You are **not** deploying to anyone or touching user data.
- **Tone:** reassuring, second-person, jargon-deferred. No credentials asked here.
- **Actions:** Primary `Get Started` → stage 2. Secondary `Quit`.
- **Symbol:** `checkmark.seal`.

### 3.2 Prerequisites checklist, stage 2

- **Purpose:** Educate on the four Apple prerequisites before any credential entry.
- **Layout:** eyebrow "BEFORE YOU BEGIN" → title "What Apple needs from you" → intro `.body`.
  Then a **single grouped card** (radius 10, contentSurface) containing four `PrerequisiteRow`s
  (§4.1), each: leading SF Symbol (membership/certificate/intermediate/appPassword per §1.8), title
  (`.body` medium), one-line why (`.callout` secondary, 2-line clamp), trailing `Learn More` (`.link`
  or `.bordered` small). Replaces the current green-check rows.
- **Tone:** "here's the map, open any item you're unsure about."
- **Actions:** Primary `Continue`. Secondary `Back`.
- **Symbol:** `checklist`.

### 3.3 Prerequisite Guide (detail, x4), stage 2 sub-state

- **Purpose:** Teach one prerequisite (`PublisherGuide` cases). This is the canonical **teach step**
  (§4.2).
- **Layout:** eyebrow "PREREQUISITE 2 OF 4" (numbered!) → title (`guide.title`) → `guide.why` as
  `.body`. Then **"How to check this"** section: numbered steps (§4.2) using the existing `guide.steps`.
  For `.certificate`, include the verification `commandBlock` (§4.4) with copy. When
  `guide.actionURL` exists, a **prominent "Open …" button with `arrow.up.forward.app`** launches the
  Apple web console.
- **Actions:** Primary = `guide.actionTitle` open button when present, else `Continue`. Secondary
  `Back to Checklist`. Tertiary text-link `Skip to Setup`.
- **Symbol:** per-guide (§1.8).

### 3.4 Signing Identity detect (split from form), stage 3

- **Purpose:** Detect & choose the Developer ID Application identity; surface Team ID immediately.
  This is a **verify step** (§4.3) over `security find-identity`.
- **Layout / states:**
  - **Detecting:** centered `magnifyingglass` + `ProgressView` + "Looking for Developer ID
    Application certificates…" (`.callout`).
  - **Found (≥1):** card with `checkmark.seal.fill` (green) header "Signing identity found." A
    `Picker` (labelsHidden, native) if >1; single row if one. Below: **Team ID** shown large and
    monospaced in its own inset (`fieldSurface`, `number` glyph, `.textSelection(.enabled)`) with a
    caption "Extracted automatically, you'll hand this to Admin later." `Refresh` as a small
    secondary/`.borderless` icon button (`arrow.clockwise`).
  - **None found:** `exclamationmark.shield.fill` (orange) "No Developer ID Application certificate on
    this Mac." Recovery `.body` + a `Learn More` back to the certificate guide. **Not a dead end**:
    primary becomes `Recheck`, secondary `Open Certificate Guide`.
- **Tone:** matter-of-fact, celebratory-lite on success.
- **Actions:** Primary `Continue` (disabled until an identity is selected). Secondary `Back`.
- **Symbol:** `person.badge.key`.

### 3.5 Cert-Trust Verify (NEW, critical), stage 4

- **Purpose:** The single most common stranding point. After an identity exists, verify the cert
  **(a) has its private key** and **(b) chains to a trusted anchor**, and if untrusted, guide the
  **correct** fix (install Apple's Developer ID – G2 intermediate): **never** suggest right-click →
  "Always Trust," which is the wrong, security-degrading fix.
- **Detection (render, don't compute policy):** run non-destructive checks and render results:
  - Private key: `security find-identity -v -p codesigning` already proves a usable key/identity pair;
    surface pass/fail from whether the chosen identity is present as a *valid* identity.
  - Trust chain: attempt a dry `codesign`/`security verify-cert`-style check (implementer picks the
    least-privileged read-only probe; e.g. `security verify-cert -c <cert>` or evaluate the SecTrust
    of the identity's cert). Render: trusted / untrusted-but-fixable / broken.
- **States:**
  - **Verifying:** `ProgressView` + "Checking this certificate's key and trust chain…"
  - **Trusted + key present (pass):** big `checkmark.shield.fill` (green, palette) → "This certificate
    is trusted and ready to sign." Two-line checklist: ✓ Private key present · ✓ Chain trusted.
    Primary `Continue`.
  - **Untrusted but fixable (warn):** `exclamationmark.shield.fill` (orange) → "macOS doesn't fully
    trust this certificate yet." Body explains: the usual cause is a missing **Developer ID – G2**
    intermediate; installing Apple's intermediate completes the chain. **Explicit anti-guidance
    callout** (a bordered `.callout` note with `hand.raised` glyph): "Don't use Keychain's *Always
    Trust*, it hides the problem locally and won't make your release trusted on other Macs." Primary
    `Open Apple Certificate Authority` (`arrow.up.forward.app` → the CA page), Secondary `Re-verify`
    after install. Never blocks forever: after install the user re-verifies.
  - **Missing private key (fail):** `xmark.shield.fill` (red) → "This certificate has no private key on
    this Mac." Body: you must recreate the certificate from a CSR generated on this Mac (can't be
    exported without the key). Primary `Open Certificate Guide`, Secondary `Re-verify`.
- **Tone:** precise, reassuring, corrective without condescension; the anti-"Always Trust" note is the
  hero content.
- **Symbol:** `checkmark.shield` / state variants above.

### 3.6 Notary & Release Config (from `.form`), stage 5

- **Purpose:** Store the notary profile (`xcrun notarytool store-credentials`) and write
  `.env.release.local`. Keep existing model fields and `setup()` logic.
- **Layout:** two grouped cards under one step:
  - **Card A (Notary credential):** intro `.callout` ("stored in your Keychain; the password goes only
    to Apple's tool, never the repo"). Fields (§4.5 form rows, label-left 112pt): Apple ID Email
    (`TextField`, `.roundedBorder`), Profile name (`TextField`, default `ct-notary`), a **Secure**
    password field (§4.6) with `key.horizontal` leading glyph, and a `Toggle("Skip notarization")`
    (`.switch` style, not checkbox: more native/legible) that disables the credential fields with a
    caption explaining the consequence ("the artifact won't be notarized, only do this to test the
    build").
  - **Card B (Release config):** env file path (`TextField`, default `.env.release.local`) + a
    `Toggle("Replace existing file")` `.switch`. Caption: "Non-secret settings, git-ignored,
    owner-only permissions."
- **Validation:** inline, per-field, on submit: surface the model's existing `status` string as a
  `.callout` in `danger` next to the offending field rather than one bottom-of-form line. Never clears
  the form on error.
- **Actions:** Primary `Set Up Publisher Machine` (shows inline `ProgressView` + "Setting up…" when
  `isRunning`; disabled if no identity). Secondary `Back`.
- **Symbol:** `paperplane` (notary), `doc.badge.gearshape` (config).

### 3.7 Pre-Build Review (NEW micro-state before build), stage 5→6 seam

- **Purpose:** A calm confirmation before the long, irreversible-feeling build. Reduces "did I do this
  right?" anxiety. Corresponds to the current `.success` screen's summary, repurposed as a *review*.
- **Layout:** title "Ready to build the release." A **read-only summary card** (`summaryRow` style,
  §4): Signing identity · Team ID · Notary profile (or "Skipped") · Env file. Then a `.callout`
  describing exactly what the button will do (build → sign → notarize → staple) and that it may take
  several minutes.
- **Actions:** Primary `Build, Sign & Notarize`. Secondary `Edit Setup` (→ stage 5). Tertiary
  `Copy Manual Commands` (`doc.on.doc`).
- **Symbol:** `hammer`.

### 3.8 Building / Live Log, stage 6

- **Purpose:** Run build/sign/notarize/staple with live, copyable output; never look frozen.
- **Layout:** title = current `publishStep` ("Building app…", "Signing…", "Notarizing & stapling…").
  A **step tracker** row of 3 chips (Build · Sign · Notarize) each with state glyph
  (`circle`→`circle.inset.filled` accent + `ProgressView`→`checkmark.circle.fill` green). Below: the
  **live log** panel (§4.4): monospaced, `fieldSurface`, auto-scrolls to bottom, min-height 220,
  max-height fills, `Copy Log` button. The whole screen is non-interactive except Copy; primary shows
  a disabled `ProgressView`-labeled "Building…". Keep window open message as `.callout`.
- **Tone:** transparent, patient. The log is proof-of-work, not decoration.
- **Symbol:** `hammer` (title), per-chip symbols.

### 3.9 Success / Structured Handoff, stage 7 (merges `.success`+`.published`)

- **Purpose:** Confirm the artifact exists AND give a **copyable Publisher → Admin handoff block**.
  This is the finish line and the audit-required deliverable.
- **Layout:** `checkmark.circle.fill` / `shippingbox.fill` (green, 48pt) hero → title "The release is
  signed and ready for Admin." Then:
  - **Card (Handoff block, hero):** a monospaced, selectable, **one-tap-copy** block (§4.4 with a
    prominent `Copy Handoff` primary-tinted copy button) containing exactly:
    ```
    PUBLISHER → ADMIN HANDOFF
    App:              <artifact.appPath>
    Disk image:       <artifact.dmgPath>
    Team ID:          <selectedIdentity.teamId>
    Signing identity: <identity.name>
    Version:          <appVersion>            # read from tauri/Info.plist
    Notarized:        Yes | No (skipped)
    Update signing:   Ready | Not ready (<reason>)
    Produced:         <ISO date, this Mac>
    ```
    "Update signing" status is explicit ready/not-ready per invariant #4 (never silently implies
    ready). If notary was skipped, "Notarized: No (skipped)" in `warning`.
  - **Card (What was produced):** `summaryRow`s for App / DMG paths (selectable, mono) with a
    `Reveal in Finder` button (`arrow.up.forward.app`/`folder`) per path.
  - **Disclosure, Publishing log:** collapsed `DisclosureGroup` "Show build log" → the full log
    (§4.4), so the finish screen stays calm but the proof is one click away.
  - **Callout (Next role):** one `.callout` explaining Admin deploys this; publisher's job is done.
- **Actions:** Primary `Copy Handoff` (or `Done` if already copied, show `copiedMessage`).
  Secondary `Reveal Artifacts`. Tertiary `Quit`.
- **Symbol:** `shippingbox.fill`.

### 3.10 Failure: inline, contextual (not a separate dead-end screen)

- **Purpose:** Explain the failure, name the fix, keep output copyable, never dead-end.
- **Layout:** Reuse the current screen's structure but re-skinned: `exclamationmark.triangle.fill`
  (red, palette) → title (`failure.title`) → `failure.message` (`.body`). **"What to do next"** card
  with `failure.recovery` and, when present, a prominent `failure.actionTitle` button
  (`arrow.up.forward.app`). **"Details"** = the log/details in a §4.4 block with `Copy Details`; if it's
  a build failure, **highlight the first failed command** (§4.4) so the eye lands on the actual error.
- **Tone:** blameless, specific, actionable. Every failure names a next action.
- **Actions:** Primary `Try Again` (routes back to the relevant stage, not always the form, e.g.
  credential rejection → stage 5, build failure → stage 6 review). Secondary `Quit`.
- **Symbol:** `exclamationmark.triangle.fill`.

---

## 4. Component Patterns

### 4.1 `PrerequisiteRow` (checklist item)
`HStack(spacing 12)`: leading SF Symbol (20pt frame, hierarchical, tintBlue) · `VStack` title
(`.body` medium, `label`) + why (`.callout`, `secondaryLabel`, 2-line clamp) · `Spacer(min:12)` ·
trailing `Learn More` (`.link` style or small `.bordered`). Row vertical padding 8. Divider between
rows inside the card (hairline `separator`, inset to text).

### 4.2 Teach step (guide) pattern
Anatomy: numbered eyebrow → title → why (`.body`) → **"How to check this"** section with
`NumberedStep`s. `NumberedStep`: leading number in a 22pt circle (`separator` @35% fill, `.caption`
semibold `label`) + step text (`.callout`, `secondaryLabel`). When a console URL exists, the **web
button is prominent** and uses `arrow.up.forward.app` to signal "leaves the app to Apple's site."
Optional verification `commandBlock`.

### 4.3 Verify step pattern (detect → result)
Three visual states share one container:
- **Detecting:** centered `ProgressView` + `.callout` status, subtle.
- **Pass:** filled shield/seal glyph in `success` (palette), one-line result title, a compact
  ✓-list of what passed.
- **Fail/Warn:** filled glyph in `danger`/`warning`, plain-language cause, a **fix affordance**
  (button/guide link), and a `Re-verify` secondary. Never a state with no forward action.
Status is glyph + color + text (never color alone). Used by 3.4, 3.5.

### 4.4 Live log / code block
- Container: `fieldSurface`, radius 10, mono `.body`, `.textSelection(.enabled)`, 12 padding.
- Sizing: min-height 96 (static command) / 220 (live log), grows to fill, internal `ScrollView`.
- **Live log:** auto-scroll to newest line (`ScrollViewReader` → scroll to bottom anchor on append).
- **First-failed-command highlight:** when a step fails, the log renders the failing `$ command` line
  and its error region with a `danger`-tinted left border (3pt) + faint `danger` @8% background behind
  those lines, and auto-scrolls to it. Implementer: tag the failing line index from the exit-status
  boundary already tracked in `runReleaseStep`.
- **Copy button:** `.bordered` with `doc.on.doc` + label; sets `copiedMessage` (fades after ~2s).

### 4.5 Form field row
`HStack`: trailing-aligned label (112pt, `.callout` medium `secondaryLabel`) · control fills. Control
uses native `.roundedBorder` `TextField`. Caption (`.caption`, `tertiaryLabel`) sits **below** the
control in a `VStack`. Inline error replaces caption in `danger` when invalid. Keep native styling:
do not custom-draw fields.

### 4.6 Secure input
`SecureField` `.roundedBorder` with a leading `key.horizontal` glyph (via `.overlay` or an `HStack`
label). Caption spells out "app-specific password, not your Apple ID password." A trailing
`eye`/`eye.slash` reveal toggle is optional (nice-to-have; default hidden). Disabled + dimmed when
"Skip notarization" is on, with the caption switching to explain why it's disabled.

### 4.7 Primary / secondary buttons
- **Primary:** `.borderedProminent` + `.keyboardShortcut(.defaultAction)`, bottom-trailing, tinted by
  system `controlAccentColor`. **Do not** set a fixed white `foregroundColor` or fixed widths; let the
  native prominent style + intrinsic sizing handle contrast in light/dark. (Current code hardcodes
  `.white` and `frame(width:)`: remove both; they fight the platform.)
- **Secondary:** `.bordered`, leading. **Destructive** (none here except Quit, which is neutral).
- **Tertiary:** `.borderless`/`.link` for "Copy Manual Commands," "Skip to Setup."
- One primary per screen. Cancel/Quit maps to `.keyboardShortcut(.cancelAction)`.

### 4.8 Roadmap sidebar row
`Label`-style: leading status glyph (done `checkmark.circle.fill` success / current
`circle.inset.filled` accent / upcoming `circle` tertiary) + stage name (`.body`; current = `.medium`
`label`, others `secondaryLabel`). Current row: accent-tinted pill background (radius 6, accent @12%).
Done rows tappable (review), upcoming rows disabled (dimmed, not tappable). Section header "SETUP"
(`.caption` uppercase secondary) above the list.

---

## 5. Motion

Minimal, native, purposeful: HIG restraint.

| Interaction | Treatment | Token |
|---|---|---|
| Step ↔ step (content pane) | Cross-fade + 8pt slide-in from trailing (`.transition(.opacity.combined(with: .move(edge: .trailing)))`), driven by `.animation(.easeOut(duration: 0.2), value: phase)` | normal / ease-out |
| Roadmap current marker advancing | The active pill + glyph animate to the next row (`.easeInOut(0.25)`) | slow / ease-in-out |
| Verify detecting → result | Cross-fade (0.2), result glyph a subtle scale-in (`.spring(response: 0.3, dampingFraction: 0.8)`), one small moment of delight on pass | normal |
| Field validation error appear | Fade-in caption→error (0.15), no shake | fast / ease-out |
| Long build progress | Indeterminate `ProgressView` per active step chip + the streaming log itself is the progress signal (honest: real output, not a fake bar). Optional determinate bar only if step count is known (3 steps → 33/66/100%). | N/A |
| Copy confirmation | `copiedMessage` fades in (0.15) and out after ~2s (0.3 ease-in) | fast/normal |

Rules: ease-out for entering, ease-in for exiting, ease-in-out for the roadmap marker moving between
positions. No bounce on navigation. Respect **Reduce Motion**: when set, replace slides with plain
cross-fades and drop the spring scale-in.

---

## 6. Accessibility

- **Dynamic Type:** use semantic `Font` styles (§1.4) throughout so text scales; verify layout holds
  at XL sizes (content column reflows, cards grow vertically, no clipped titles,
  `.fixedSize(vertical)` on titles/body). No hardcoded `.system(size:)`.
- **VoiceOver:**
  - Roadmap rows: `.accessibilityLabel("Step 3 of 7, Signing Identity, current")` /
    "…completed" / "…not started"; group as an accessibility container labeled "Setup progress."
  - Status glyphs: every status conveys via `.accessibilityLabel` ("Verified," "Needs attention,"
    "Failed"), never rely on the symbol/color alone.
  - Team ID / paths / handoff block: `.accessibilityLabel` reading the value; the copy button labeled
    "Copy handoff block."
  - Live log: `.accessibilityLabel("Build log")`; announce step transitions via
    `.accessibilityValue` updates or an `AccessibilityNotification`.
- **Contrast:** all text via system semantic label colors on system backgrounds → guaranteed AA. The
  handoff/log mono text is `label` on `fieldSurface`. Status color is always backed by text + glyph,
  satisfying color-independence. Respect **Increase Contrast** (system colors adapt automatically).
- **Keyboard & focus order:** logical top-to-bottom, left-to-right per screen; primary =
  `.defaultAction` (Return), Quit/Back = `.cancelAction` (Esc). Text fields in a `FocusState` chain
  (Apple ID → Profile → Password → env) with Tab traversal. Focus ring is the system ring; do not
  restyle. On each step change, move focus to the step title or first control
  (`.accessibilityFocused` / `@FocusState`).
- **Hit targets:** all buttons ≥ standard control height (native ≥ 20pt visual, ≥ 44pt effective via
  padding for any icon-only control like Refresh/reveal). Icon-only buttons get `.help()` tooltips +
  accessibility labels.
- **Reduce Motion / Reduce Transparency:** honor both: when Reduce Transparency is on, the sidebar
  material falls back to an opaque system color automatically (system handles it); don't override.

---

## 7. Implementation Notes (deltas from current code)

1. **Introduce `NavigationSplitView`** with a fixed roadmap sidebar; move the `switch phase` content
   into the detail column. Add `RoadmapStage` enum + `currentStage(for:)`.
2. **Add three phases:** `.welcome`, `.identity`, `.trustVerify`; split notary/env out of the old
   combined `.form` intro; merge `.success`+`.published` into one handoff outcome (keep both structs).
3. **Delete hardcoded type sizes** → semantic `Font`. **Delete `foregroundColor(.white)` and
   `frame(width:)` on buttons** → native prominent/bordered intrinsic sizing.
4. **Adopt the 8pt spacing scale**, radius 10 on cards, and the pinned footer action bar.
5. **Toggles:** switch checkbox → `.switch` where it's a mode (skip notary, replace file).
6. **Cert-trust probe:** add a read-only trust/key verification (SecTrust evaluation or
   `security verify-cert`) feeding the §3.5 states; render results, encode no trust policy (invariant
   #1). Never auto-run "Always Trust."
7. **Handoff block:** assemble the §3.9 string from `selectedIdentity.teamId`, artifact paths, app
   version (read from bundle/Info.plist or `tauri.conf.json`), and an explicit update-signing status
   flag (default "Not ready, updater signing not configured" unless proven).
8. **Live-log first-failure highlight:** tag the failing command boundary already known from
   `requireReleaseStepSuccess` exit status; render that line region with the `danger` treatment (§4.4).
9. Keep all `Process`/CLI logic, parsing, and error mapping intact: this is a re-skin + restructure,
   not a rewrite of behavior.

---

## Sources

- [Apple Human Interface Guidelines: Home](https://developer.apple.com/design/human-interface-guidelines/)
- [HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
