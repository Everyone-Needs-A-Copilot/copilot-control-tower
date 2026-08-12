# Copilot Control Tower: Native macOS Visual Design System

Stage 3 of 3 of the native-app redesign (Stage 1 = structure / IA / state inventory in
`control-tower-native-experience-architecture.md`; Stage 2 = interaction in
`control-tower-interaction-spec.md`; this = the **visual system**: color, material,
type, iconography, spacing, elevation, motion, and per-component / per-screen visual
specs). It dresses the interaction layer Stage 2 defined; it invents no new flow,
state, or copy. It is implementer-ready for SwiftUI / AppKit.

**This is the corrected rewrite on the CSE domain.** The prior visual system's visual
**language** (the "Quiet Instrument" north star, the scarce semantic color ramp, the
brand-navy discipline, the `NSVisualEffectView` materials, the SF Pro type scale, the
12 shape-first badge tokens, spacing / radii / elevation, motion + Reduce Motion,
accessibility + grayscale proof, and the Publisher Setup family coherence) was roughly
95% domain-neutral and is **reused verbatim**. What changed is the **domain the
language dresses**: the popover now renders CSE-**component** currency (Knowledge /
CLI / Claude / Codex Copilot) across the **entitled inheritance layers**, plus the new
department-join, the shared-versus-personal integration split, the personal-key
multi-machine sync, and an Admin mode of Onboarding + Governance with **no MDM and no
fleet-as-center**. Sections 1 to 5 (the language) are kept; sections 6 and 7 (the
components and per-screen direction) are re-authored for the corrected surfaces
S1 to S13.

- **Mode: Controlled.** This is macOS. We do not invent a web-style design system that
  fights the platform; we commit to the Apple platform vocabulary (system semantic
  colors, `NSVisualEffectView` materials, SF Pro, SF Symbols, native controls). The
  craft is restraint, spacing, hierarchy, honest status, and never-dead-end states.
- **Family coherence:** this system is the sibling of `publisher-setup-visual-spec.md`.
  It reuses that spec's tokens, roadmap-sidebar grammar, component patterns, and motion
  wholesale for its windowed surfaces, and extends the family into a **menu-bar
  instrument register** (the glyph + popover) that Publisher Setup does not have. The
  two apps must read as one design team's work.

Hard constraints honored throughout (owner-sourced, Stage 1 anti-patterns, SOUL):
no purple filled header bar (brand navy survives **only** as the monochrome template-
glyph tint, never a filled banner); no em-dashes in any copy; no fake-healthy or
celebratory states (including no rendering an entitled-not-synced layer or an
unresolved shared integration as green); no health scores, rings, or sparklines; no
ETAs or countdowns; **status is legible shape-first and survives being stripped of
color** (color is a second channel only); native materials, system semantic colors,
SF Pro, SF Symbols; light + dark, Dynamic Type, Reduce Motion; **no MDM / managed-key /
fleet-as-center visuals**; components, never products.

---

## 1. Design language / north star (reused verbatim)

**Named direction: "Quiet Instrument."** The visual character of a first-party Apple
system utility that lives in the menu bar and speaks like an air-traffic-control panel:
monochrome and silent by default, precise when it has something to say, never
decorative. Depth comes from real macOS materials (menu-bar vibrancy, sidebar material,
popover blur) and honest hierarchy, never from drop shadows or color fields. Its whole
aesthetic is **silence you can trust** (SOUL): the brightest, most-saturated thing on
screen is only ever the one thing that is actually wrong, and when nothing is wrong
there is nothing to see.

**Relationship to Publisher Setup.app.** Both apps belong to one family, **Native
Calm**. Publisher Setup is its **"Setup Assistant Calm"** register (a do-once, windowed
assistant); Control Tower's wizard and Admin surfaces reuse that register verbatim (the
same `NavigationSplitView` roadmap sidebar, the same card / field / button patterns,
the same color and type tokens, the same motion). Control Tower then adds the **"Quiet
Instrument"** register for its always-on face: the menu-bar glyph and the popover. A
user who set up a publisher machine and then opens Control Tower should feel the same
hand made both. The token set below is a strict superset of Publisher's, and every
shared token keeps Publisher's value.

**The one honesty rule the corrected domain adds to the language:** the tree, the
join row, and the two integration registers must each be legible as *what they honestly
are* before color. An entitled-not-synced layer reads as a hollow, joinable invitation,
never a fault and never a fake pass; a shared integration reads as inherited-and-read-
only (no sign-in affordance at all); a personal integration reads as yours-to-sign-in.
These are structural, shape-first distinctions, not color choices.

---

## 2. Color system (reused verbatim)

**Rule (inherited from Publisher, elevated to a hard a11y rule here): status is never
encoded by color alone. Every status is carried by shape (SF Symbol / badge geometry) +
text label first; color is a redundant second channel.** Nothing below may be the sole
signal of a state. See section 9 for the grayscale proof.

All values are **system semantic colors** (`NSColor` / SwiftUI `Color(nsColor:)`) that
adapt to light, dark, Increase Contrast, and the user's accent automatically. Do not
hardcode RGB anywhere except the one brand-glyph asset (2.4). The `src/styles/*.css`
literals (for example `--status-error: #c5221f`) are **reconciled to their system
semantic equivalent** below; the web hex values are retired for the native build.

### 2.1 Neutral roles (surface, content, separators)

| Role token | SwiftUI / NSColor | Light + dark usage | Replaces CSS |
|---|---|---|---|
| `content.primary` | `.labelColor` | Status sentence, component names, values | `--text-primary` |
| `content.secondary` | `.secondaryLabelColor` | Host name, body, layer detail, register labels | `--text-secondary` |
| `content.tertiary` | `.tertiaryLabelColor` | Captions, disabled reasons, not-entitled slots (>= 11pt only) | `--text-tertiary` |
| `surface.window` | `.windowBackgroundColor` | Wizard / Admin / Settings content pane base | `--surface-popover`* |
| `surface.card` | `.controlBackgroundColor` | Grouped cards, inset panels, Bob-lane card, register groups | `--surface-raised` |
| `surface.field` | `.textBackgroundColor` | Text fields, code / handoff blocks, log, seed preview | `--surface-sunken` |
| `separator` | `.separatorColor` | Hairline dividers, tree indent guides, register dividers | `--separator` |
| `accent` | `.controlAccentColor` | Primary buttons, current roadmap step, focus | (respect user accent) |

*The popover surface is **not** a flat fill: it is the system `NSVisualEffectView`
`.popover` / `.menu` material (see section 5 materials), so `surface.window` is only
the opaque fallback under Reduce Transparency.

### 2.2 The status / severity ramp (second channel only)

Each status pairs a **shape** (section 4) with one system color. The colors are
deliberately restrained: most states are neutral / gray (calm, "not an emergency"),
exactly one state is red, and there is no green anywhere except the row-level `pass`
dot.

| Status token | Color (system) | Why this color | Shape carries it (section 4) |
|---|---|---|---|
| `healthy` (row `pass` dot only) | `.systemGreen` | The single, quietest green; **row-level only, never the tray, never a fill** | small filled dot |
| `setup-needed` | `.secondaryLabelColor` | Neutral: an invitation, not an alarm. **Also the color of the entitled-not-synced Join row** | hollow ring |
| `it-config-incomplete` | `.secondaryLabelColor` (desaturated gray) | "Not yours; IT owns this" reads as calm gray, not warning | wrench |
| `waiting-for-network` | `.secondaryLabelColor` | Patient, transient, nobody's fault | clock |
| `offline` | `.secondaryLabelColor` | Same neutral family as waiting | cloud-slash |
| `syncing` | monochrome glyph tint (no ramp color) | Work in progress is not a severity; it stays the plain glyph color | circular arrows |
| `signed-out` | `.systemBlue` | Actionable-by-you, informational blue (not alarm). **The Personal integration register's only accent** | key |
| `update-available` | `.systemBlue` | Informational; transport handles it, not urgent | download arrow |
| `needs-attention` | `.systemOrange` | The one amber: something needs a look, still not critical | filled triangle |
| `updating-app` | `.secondaryLabelColor` | Transport in progress, neutral | spinner / install arrow |
| `cli-unreadable` (`bang`) | `.systemRed` | **The only red in the product.** Honest "I won't guess" | filled circle + `!` |

Note the deliberate scarcity: gray dominates, blue is "you can act", orange is the
single "look at this", red is unique to the one honest-degrade state. This is the
severity grammar SOUL demands: the brightest mark is always the truest problem. **The
Shared integration register carries no ramp color at all** (2.6 / 6.2): "available" is
a neutral gray marker, and its honest-degrade "not available right now" is neutral gray
too (it is not the user's to fix, so it never earns red or orange on his surface).

### 2.3 Where brand color appears (and where it must not) (reused verbatim)

The brand navy **#2D294E** (dark) / its light-mode companion **#B4AEE8** (from the CSS
dark ramp) is **not** a UI color in this system. It appears in exactly two places:

1. **The menu-bar template glyph tint** (2.4): as a *template* image, so it renders
   monochrome in the menu-bar foreground color, not as literal navy.
2. **The one place the literal navy is allowed to show as itself:** the app's own brand
   mark at large size in **About** (S10) and, optionally, the wizard / Admin sidebar
   app-label glyph, rendered as a full-color (non-template) brand asset. This is a small
   mark, never a bar, banner, or field.

**Forbidden (owner-sourced):** no purple / navy filled header bar, no colored popover
header, no navy card, no navy button fill, no navy behind text. `accent` for primary
actions is the **user's system accent**, never the brand navy.

### 2.4 The menu-bar template glyph (the identity, monochrome) (reused verbatim)

- **Asset:** the aviator-sunglasses silhouette (Founding Decision #4), authored in
  brand navy `#2D294E`, delivered to `NSStatusItem` as a **template image**
  (`NSImage.isTemplate = true`). As a template, macOS discards the asset's own color and
  renders the silhouette in the correct **menu-bar foreground color**: black-ish in
  light menu bars, white in dark menu bars, inverted when the item is highlighted / open,
  and tinted by the system when appropriate. This is the honest native behavior and it
  is why the navy never shows as navy in the bar. Rasterize from the source SVG at build
  time to the target point size at @1x / @2x / @3x.
- **Size:** the glyph occupies roughly **16 to 18pt** of visual height inside the ~22pt
  menu-bar item (`NSStatusItem.squareLength`), matching system menu-bar extras (Wi-Fi,
  Battery). Optically center; the sunglasses silhouette should sit on the same baseline
  as adjacent system extras.
- **Badge overlay (the state, shape-first):** the base glyph is always the same
  silhouette. State is expressed by a **small badge composited at the bottom-trailing
  corner** of the glyph (like a system status pip), sized roughly **8 to 9pt**. The badge
  is the section 4 shape. Because the base is a template (monochrome), the badge is where
  the optional **second-channel color** lives: the composite image is rendered
  `isTemplate = false` only when a colored badge is present, so the badge's system color
  (for example red for `bang`, orange for `needs-attention`) shows while the silhouette
  still reads as the menu-bar foreground. The badge's **shape** is the primary encoder
  and reads in pure monochrome; the color is redundant.
- **`none` (Healthy) is bare:** no badge, no pip, no color, no decoration. Pure
  silhouette in the menu-bar foreground color. Silence is the success state (SOUL): the
  glyph you cannot distinguish from "off" is the glyph saying everything is fine.
- **Entitled-not-synced does not nag the tray.** A department the user is entitled to
  but has not joined is a quiet popover Join row (2.6 / 7.2), **not** a tray badge. The
  glyph only rises to `hollow` (setup-needed) when the machine genuinely has no joined
  layers yet (Stage 1). The tray never invents urgency for an optional join.
- **VoiceOver:** `accessibilityLabel` = the current status sentence; `accessibilityValue`
  = the state name ("needs sign-in", "offline", "error, cannot read setup", "a
  department is available to join"); `role` = button. Never the SF Symbol name.

---

## 3. Typography scale (reused verbatim)

Use **semantic `Font` styles** (SF Pro, via SwiftUI `Font`), never hardcoded
`.system(size:)`, so Dynamic Type and SF optical sizing work (deletes the web
`--type-*-size` point literals). Two registers: the **compact popover** and the **roomy
windows** (wizard / Admin / Settings, which reuse Publisher's scale exactly).

### 3.1 Popover register (compact)

| Role | SwiftUI Font | Weight | Where |
|---|---|---|---|
| Status sentence | `.headline` | `.semibold` | Region 1, the one honest line |
| Host name | `.subheadline` | `.regular`, `content.secondary` | Under the sentence, quiet |
| Component row name | `.body` | `.regular`, `content.primary` | Region 2 component disclosure rows |
| Layer cell name | `.subheadline` | `.regular`, `content.secondary` | Nested layer cells (foundation / org / dept / personal) |
| Row detail / caption | `.caption` | `.regular`, `content.tertiary` | Truncated `detail`, inline reasons, not-entitled slot text |
| Register group label | `.caption` | `.semibold`, `.textCase(.uppercase)`, `content.secondary` | "SHARED", "PERSONAL", "AVAILABLE TO JOIN" |
| Register label subtitle | `.caption` | `.regular`, `content.tertiary` | "Available because you're entitled" / "Your accounts" |
| Action button label | `.body` | native | Region 5 (native `.bordered`) and the Join button |
| Bob prompt title | `.body` | `.medium`, `content.primary` | Bob-lane card |
| Bob notice line | `.subheadline` | `.regular`, `content.secondary` | Past-tense notices |
| Security banner label | `.subheadline` | `.medium` | Pinned banner text |

Popover body wraps, never truncates the status sentence
(`.fixedSize(horizontal: false, vertical: true)`); layer / integration `detail` may
truncate with a `.help` + VoiceOver-value full string.

### 3.2 Window register (wizard / Admin / Settings): reuse Publisher

| Role | SwiftUI Font | Weight | Where |
|---|---|---|---|
| Screen hero title | `.largeTitle` | `.semibold` | Wizard Welcome / Done hero only |
| Step / pane title | `.title` | `.semibold` | Every wizard step H1, every Admin / Settings detail-pane H1 |
| Section header | `.title3` | `.semibold` | Card / form-section titles, register headers in windows |
| Eyebrow / kicker | `.caption` | `.semibold`, `.textCase(.uppercase)`, `.systemBlue` | "STEP 5 OF 10", "ONBOARDING" |
| Body | `.body` | `.regular`, `content.secondary` | Intros, descriptions, what-syncs / what-never blocks |
| Emphasis body | `.body` | `.medium`, `content.primary` | Checklist / row titles, key labels, machine names |
| Callout | `.callout` | `.regular` | Helper text under fields, scope lines |
| Caption | `.caption` | `.regular`, `content.tertiary` | Field captions, hints |
| Mono value | `.body`, `.monospaced()` | `.regular` / `.semibold` | Team ID, handoff block, `user_code`, machine IDs, repo URLs, log, seed preview |

Line spacing: default leading; `.lineSpacing(2)` on multi-line body; titles / body get
`.fixedSize(horizontal: false, vertical: true)` to wrap, never clip, at XL Dynamic Type.

---

## 4. Iconography: the 12 badge tokens (shape-first, grayscale-distinct) (reused verbatim)

Each `BadgeState` token maps to one SF Symbol whose **silhouette is unique**, so every
state is distinguishable by shape alone in grayscale, color-blind, and Reduce-Motion
renders simultaneously (SOUL: "shape is the first encoder, color the second"). The
"Silhouette class" column proves the shapes do not collide. **The token set is closed
and unchanged by the domain correction.**

| Token | SF Symbol | Silhouette class (grayscale-distinct) | Second-channel color (2.2) | Motion (section 8) |
|---|---|---|---|---|
| `none` | *(no badge; bare glyph)* | absence | none | none (silent) |
| `hollow` (setup-needed / entitled-not-synced) | `circle` | open ring, unfilled | `content.secondary` | slow pulse to static ring |
| `wrench` (it-config-incomplete) | `wrench.adjustable` | tool | `content.secondary` (gray) | none |
| `clock` (waiting-for-network) | `clock` | dial + hands | `content.secondary` | none |
| `cloud-slash` (offline) | `cloud.slash` | cloud + slash | `content.secondary` | none |
| `ring` (syncing) | `arrow.triangle.2.circlepath` | two circular arrows | glyph tint (no ramp color) | rotate to static arrows |
| `key` (signed-out, personal only) | `key.fill` | key | `.systemBlue` | none |
| `update` (update-available) | `arrow.down.circle` | down-arrow in circle | `.systemBlue` | none |
| `triangle` (needs-attention) | `exclamationmark.triangle.fill` | filled triangle | `.systemOrange` | none |
| `spinner` (updating-app) | `ProgressView().circular` to static `square.and.arrow.down` | indeterminate spinner / box + down-arrow | `content.secondary` | spin to static box-arrow |
| `bang` (cli-unreadable) | `exclamationmark.circle.fill` | filled circle + `!` | **`.systemRed` (only red)** | none |
| `pass` (row dot only) | `circle.fill` (small) | small solid dot | `.systemGreen` | none |

Collision check on the three "!"-adjacent and three "motion" states, the only risky
pairs: `needs-attention` is a **triangle**, `bang` is a **circle** (distinct silhouette
even in monochrome); `syncing` is **two circular arrows**, `update-available` is a
**down-arrow-in-circle**, `updating-app` static is a **box-with-down-arrow** (three
distinct shapes). No two badges share a silhouette.

**One corrected mapping note (no new token):** `hollow` (the setup-needed open ring)
does double duty as the honest shape for an **entitled-not-synced** layer or Join-row,
because both mean "an invitation you can act on, not a fault and not a pass". It stays
`content.secondary` neutral gray and never becomes green, orange, or a bright "new!"
mark (fake-healthy and celebration are both forbidden here).

### 4.1 Popover / wizard / Admin action + register symbols (corrected: MDM / fleet removed, new surfaces added)

Reuse the Publisher family so the two apps' iconography matches. Symbols use
`.hierarchical` rendering by default, `.palette` for two-tone status marks; point size
tracks the adjacent text style. Rows marked **[new]** are the corrected surfaces; rows
marked **[removed]** are dropped by D4 (no MDM, no fleet-as-center).

| Action / element | SF Symbol | Surface | Rendering |
|---|---|---|---|
| Sync now | `arrow.triangle.2.circlepath` | popover action | monochrome |
| What changed | `clock.arrow.circlepath` | popover action | monochrome |
| Sign in (personal only) | `key.fill` | popover Personal register / Bob prompt | hierarchical |
| Open Sign-in Page (leaves app) | `arrow.up.forward.app` | sign-in panel / sheet | monochrome |
| Copy code / value | `doc.on.doc` | sign-in, handoff, machine IDs, PR ref | monochrome |
| Set up | *(text button, no icon)* | popover / setup-needed | n/a |
| **Join (a department)** **[new]** | *(text button, no icon)* | popover Join row / departments list | n/a |
| **Shared integration register label** **[new]** | `building.2` | popover + Settings Shared group header | hierarchical, `content.secondary` |
| **Shared integration row, available** **[new]** | `circle.fill` (small, neutral) | Shared register row | monochrome `content.secondary` (never green) |
| **Shared integration row, not available now** **[new]** | `circle` (small, hollow, neutral) | Shared register row | monochrome `content.secondary` (never red / orange) |
| **Personal integration register label** **[new]** | `person.crop.circle` | popover + Settings Personal group header | hierarchical, `content.secondary` |
| **Personal integration row, signed in** **[new]** | `circle.fill` (small, neutral) | Personal register row | monochrome `content.secondary` (calm, no green reward) |
| **Personal integration row, signed out** **[new]** | `key.fill` | Personal register row | `.systemBlue` (the actionable blue) |
| **Department, available to join** **[new]** | `circle` (hollow) | departments list / Join row | `content.secondary` (setup-needed shape) |
| **Department, joined** **[new]** | `circle.fill` (small, neutral) | departments list | `content.secondary` (quiet, not celebratory) |
| **Department, not available to you** **[new]** | *(no mark; text only)* | departments list | `content.tertiary` |
| Preferences | `gearshape` | right-click menu | monochrome |
| Re-affirm your version | `checkmark.shield` | security banner | hierarchical |
| Review your changes (dirty-wip) | `folder` | dirty-work panel | hierarchical |
| Admin: Prerequisites & contacts | `checklist` | Admin sidebar | hierarchical |
| Admin: GitHub topology | `point.3.connected.trianglepath.dotted` | Admin sidebar | hierarchical |
| Admin: Authors & SSH keys | `person.badge.key` | Admin sidebar | hierarchical |
| **Admin: Team access & entitlement** **[new]** | `person.2.badge.key.fill` | Admin (per-department grant) | hierarchical |
| **Admin: Central shared secret store** **[new, replaces managed keys]** | `lock.doc` | Admin sidebar (Onboarding + Governance config) | hierarchical |
| Admin: Seed generator | `doc.badge.gearshape` | Admin sidebar | hierarchical |
| Admin: Policy signers | `signature` | Admin sidebar | hierarchical |
| Admin: Preflight | `checklist.checked` | Admin sidebar | hierarchical |
| Admin: Deprovision (by revocation) | `person.badge.minus` | Admin Governance | hierarchical |
| Admin: Analytics (opt-in copy, not a health chart) | `chart.bar.doc.horizontal` | Admin Governance | hierarchical |
| **Settings: Personal Key Sync (S13)** **[new]** | `key.icloud` | Settings tab + roster header | hierarchical |
| **Personal-key roster: this Mac / a machine** **[new]** | `laptopcomputer` / `desktopcomputer` | key-sync roster row | hierarchical |
| **Personal-key roster: enroll** **[new]** | `plus.circle` | roster row action | monochrome |
| **Personal-key roster: remove** **[new]** | `minus.circle` | roster row action | monochrome |
| Handoff header | `arrow.left.arrow.right` | Admin onboarding banner | monochrome |
| Roadmap: done | `checkmark.circle.fill` | wizard / Admin sidebar | `.systemGreen` |
| Roadmap: current | `circle.inset.filled` | wizard / Admin sidebar | `accent` |
| Roadmap: upcoming | `circle` | wizard / Admin sidebar | `content.tertiary` |
| Preflight: pass | `checkmark.circle.fill` | preflight row | `.systemGreen` |
| Preflight: fail | `xmark.circle.fill` | preflight row | `.systemRed` |
| Preflight: unknown (never green) | `questionmark.circle` | preflight row | `.systemOrange` |
| Secret-shape rejection | `hand.raised.fill` | secret-store setup field error | `.systemRed` |
| Reveal in Finder / open web | `arrow.up.forward.app` | Admin / handoff | monochrome |

**[removed] by D4 (draw nothing for these):** MDM profile generator (`gearshape.2`),
managed-key collector (`lock.rectangle.stack`), MDM upload (`arrow.up.doc`), and the
entire Fleet section (`desktopcomputer` host list, `bell.badge` actionable items).
`desktopcomputer` survives only as a per-machine glyph in the personal-key roster, not
as a fleet dashboard.

---

## 5. Spacing, sizing, radii, elevation, materials, dimensions (reused, dimensions corrected)

### 5.1 Spacing (8pt grid, reuse Publisher)

`4 (hairline) / 8 (tight) / 12 (compact) / 16 (default) / 24 (section) / 32 (pane inset)
/ 48 (hero)`. Reconciles the CSS `--space-*` scale.

- **Popover (compact register):** pane inset **12** horizontal / **12** top-bottom;
  between regions **12** with a hairline `separator`; component row height **28pt**,
  layer cells indented **16**; **integration register rows also indented 16** under
  their group label; **the two integration registers are separated by 12 + a hairline
  and each carries its own uppercase group label** (this gap is the structural
  legibility of the shared-versus-personal split, 6.2); Join row and action row gap
  **8**; Bob-lane card padding **12**.
- **Windows (roomy register):** content pane inset **32** horizontal / **24** top;
  between sections **24**; inside a card **16** padding, **12** between rows; field
  label to control **8**; sidebar row padding **8** by **12**. Admin dense rows
  (preflight, key-sync roster) use row height **32pt**.

### 5.2 Sizing / touch targets

Native control heights; all interactive controls meet the **44pt effective** target via
padding (icon-only buttons like copy / refresh / enroll / remove get `.help` + a 44pt
hit area). Popover action buttons and the Join button are standard `.bordered` height
(~28pt visual, 44pt effective row). **Read-only rows are not touch targets and get no
hit area** (the Shared register rows and joined / not-entitled rows are deliberately
inert; see 6.2 / 6.3).

### 5.3 Radii (reuse Publisher)

| Radius | Where | Character |
|---|---|---|
| **10** (`.continuous`) | Cards, panels, Bob-lane card, register group cards, log / handoff / code / seed-preview block | macOS grouped-content rounding |
| **6** (`.continuous`) | Inline chips, current-roadmap pill, owner-attribution chip, handoff chips | subtle |
| system default | Buttons, text fields, pickers, switches | **do not restyle**: native rounding is the nativeness signal |
| 50% | status dots, roadmap glyph circle | standard status dot |

Reconciles CSS `--radius-card: 8px` to **10** (Publisher's value; the family standard);
`--radius-control: 6px` to **6** for chips only, native default for controls.

### 5.4 Elevation & materials (the honest spatial model) (reused verbatim)

Depth comes from **materials and layering**, not decorative shadows. Four Z-layers,
each a real macOS material:

| Layer | Material | Shadow | Where |
|---|---|---|---|
| Ground (window content) | `.windowBackgroundColor` opaque | none (flat) | wizard / Admin / Settings content pane |
| Sidebar / chrome | `NSVisualEffectView .sidebar` (vibrancy) | none | wizard + Admin roadmap / nav sidebar |
| Cards / rows on ground | `.controlBackgroundColor` | none (flat) | all inline cards, tree rows, register cards, form cards |
| **Popover (floating instrument)** | `NSVisualEffectView .popover` / `.menu` | system popover shadow (drawn by `NSPopover`) | S1 popover |
| Panels / sheets (focused) | `.windowBackgroundColor` at `.floating` level | system window shadow | sign-in panel, dirty-work panel, conflict sheet |

The only shadow the app authors is **none**: every shadow is system-drawn by the
`NSPopover`, `NSPanel`, or sheet. Cards are flat; the popover floats because it is a
popover, the sidebar recedes because it is vibrant material against opaque content.
Under Reduce Transparency, all materials fall back to opaque system colors automatically
(do not override).

### 5.5 Window / popover dimensions (corrected for the six-region popover and the two-section Admin)

| Surface | Width | Height | Notes |
|---|---|---|---|
| **Popover (S1)** | **360pt** fixed | content-sized, **min ~96 / max ~560** then internal scroll | widened from the prior 340 to seat six regions (header, component tree, Join, two integration registers, action row, Bob lane) comfortably; Healthy shows only Regions 1 to 2 (~120pt tall) |
| **Wizard (S2)** | min **800** / ideal **920** | min **600** / ideal **700** | content column centered, `maxWidth 600`; family-consistent with Publisher; roadmap now has **10 rows** (Welcome, Detect, Choose, Your layer, Departments, Sign in, Set up, Verify, Learn, Ready) |
| **Admin (S4)** | min **900** / ideal **1080** | min **640** / ideal **760** | sidebar `min 240 / ideal 260 / max 280`; narrower than the prior fleet-era size (no dense host table); width now serves the seed form + live preview |
| **Settings (S3)** | ~**560 to 620** tabbed | content-driven | native `Settings` scene; six tabs (5.6 / 6.4) |
| **Sign-in panel (S5 steady)** | ~**420** | ~**340** | non-transient `NSPanel`, `.floating`, personal only |
| **Dirty-work panel (S6)** | ~**420** | ~**300** | non-transient `NSPanel`, `.floating` |
| **Conflict sheet (S7)** | ~**520** | content-driven | modal sheet on author window |
| **About (S10)** | standard | standard | carries the brand mark + product name |

---

## 6. Component library (visual specs, corrected surfaces)

Every component below is defined in tokens (sections 2 to 5) and specifies its eight
states where applicable (default / hover / focus / active / disabled / loading / error /
empty per Stage 2). Focus ring is **always** the system ring, never restyled (the
nativeness + a11y contract).

### 6.1 Menu-bar glyph (S1) (reused)

Per 2.4: template silhouette + optional bottom-trailing section 4 badge. Highlighted
(popover open) = system inverted template. No custom highlight color. Entitled-not-
synced does not badge the tray (2.4).

### 6.2 Popover (S1): six stacked regions (corrected core)

`NSPopover` on `.popover` material, width 360, `.transient`. Regions separated by a
hairline `separator`; a region renders only when it carries information (Healthy shows
only 1 to 2). Regions map to Stage 2 section 2.2.

- **Region 1, status header** (always present): `HStack(spacing 8)` = section 4 badge
  glyph (title-scaled, `.imageScale(.large)`) + `VStack(alignment: .leading, spacing 2)`:
  status sentence (`.headline`, `content.primary`, wraps) over host name (`.subheadline`,
  `content.secondary`). Renders `HeaderView.sentence` verbatim. Live region (polite) so a
  change while open is announced without stealing focus. No color fill behind it, ever.

- **Region 2, component-by-entitled-layer currency tree** (the corrected heart):
  SwiftUI `DisclosureGroup` per CSE **component** (Knowledge / CLI / Claude / Codex
  Copilot; the `products[]` DTO read as the component view, D2 rename pending). Component
  row = disclosure triangle + component name (`.body`, `content.primary`) + trailing
  worst-wins section 4 badge (small, with its second-channel color). Disclosed **layer
  cells** are indented 16, one per inheritance layer (foundation / org / department /
  personal), each `.subheadline` `content.secondary` + its own badge + optional truncated
  `detail` (`.caption` `content.tertiary`, full string on hover `.help` / VO value). A
  component with a non-`pass` worst severity auto-expands on first open. **Visual honesty
  rules for the tree:**
  - A layer the user is **entitled to and current** shows a quiet `pass` dot
    (`.systemGreen`, row-level only). No fill, no check reward.
  - A layer the user is **entitled to but not synced** shows the `hollow` ring
    (`content.secondary`), **never a green pass and never orange / red**. It reads as an
    open, joinable invitation, not a fault. If this is a joinable department, it is also
    surfaced as a Region 3 Join row.
  - A layer the user is **not entitled to** shows an honest empty slot: a dimmed cell,
    `content.tertiary`, no badge, with a `.caption` detail such as "You are not in this
    layer". Shown, not hidden; never a fabricated pass.
  - Skeleton rows on first paint (loading). **No project ever nests inside a layer** (the
    removed `DeptProjectView`, D8).

- **Region 3, Join available** (only if `copilot layers` reports entitled + not-joined):
  a quiet row per joinable department, `hollow` (`circle`) leading mark + department name
  (`.body`, `content.primary`) under a "AVAILABLE TO JOIN" uppercase group label
  (`.caption .semibold` `content.secondary`) + a trailing native `.bordered` **Join**
  button. Rendered as `setup-needed` neutral gray, **never a bright badge, never green,
  never an alarm**. Multiple joinable layers stack. Full state treatment in 6.2.1 and 7.2.

- **Region 4, two integration registers** (the key visual move: two registers legible at
  a glance, structurally distinct, never merged): two labeled sub-groups separated by 12 +
  a hairline `separator`.
  - **SHARED** sub-group: header row = `building.2` (`.hierarchical`, `content.secondary`)
    + "SHARED" (`.caption .semibold` uppercase `content.secondary`) with the subtitle
    "Available because you're entitled" (`.caption` `content.tertiary`) directly beneath
    the label. Rows (indented 16) = integration name (`.body`, `content.primary`) +
    trailing **state marker only, no control**: "available" is a small neutral
    `circle.fill` `content.secondary` + the word "available" (`.caption`
    `content.tertiary`); honest-degrade is a small hollow `circle` `content.secondary` +
    "not available right now". **There is no Sign in button, no chevron, no action of any
    kind, and these rows are not tab stops.** The absence of an affordance is the design:
    inherited plumbing you did not sign in for.
  - **PERSONAL** sub-group: header row = `person.crop.circle` (`.hierarchical`,
    `content.secondary`) + "PERSONAL" (`.caption .semibold` uppercase) with the subtitle
    "Your accounts" (`.caption` `content.tertiary`). Rows = integration name + state: a
    signed-out row shows the `key.fill` `.systemBlue` mark + a trailing native `.bordered`
    **Sign in** button ("Sign in to Slack") that opens the S5 panel (never inline); a
    signed-in row shows a quiet neutral `circle.fill` `content.secondary` + "signed in"
    (calm, no green reward, no nag); an `AuthIssue` expired / revoked row shows the blue
    `key` mark + "Sign in again".
  - **The glance-legible distinction, summarized:** Shared = a `building.2` group with
    neutral-gray state markers and **zero buttons**; Personal = a `person.crop.circle`
    group with **blue key marks and Sign in buttons**. Register icon + presence-or-absence
    of a blue affordance carries the distinction before any color, and the two group
    labels state the "why" in words. This split is structural (two separate groups with
    their own labels and their own row grammar), not a color nicety (D7.2).

- **Region 5, action row:** `HStack` of 0 to 3 native `.bordered` buttons (Sync now /
  What changed / Sign in), leading-to-trailing per Stage 2. States: default `.bordered`;
  hover system highlight; focus system ring; disabled dimmed + `.help` reason (Sync now
  offline: "Waiting for network"); loading = label swaps to inline `ProgressView` +
  "Syncing" and Region 1 badge shows `ring`; error is expressed only in Region 1's
  sentence, never on the button; empty = the button is absent (structural) unless the
  honest disabled-with-reason is truer. **Set up** appears in the footer for setup-needed;
  **Join** lives in Region 3, not here.

- **Region 6, Bob lane** (reused verbatim, closed sets): three registers.
  - **prompt** (`sign-in` | `dirty-wip`): inset card, `surface.card`, radius 10, padding
    12 = `BobPrompt.detail` (`.body`) + one primary `.borderedProminent` labeled
    `action_label`. Exactly one affordance; no dismiss / snooze exists. `sign-in` opens
    S5; `dirty-wip` opens S6. **A new department to join is NOT a Bob prompt** (it is the
    quiet Region 3 row).
  - **notice** (`kept-you-safe` | `kept-your-working-version` | `waiting-on-it`): quiet
    single line, neutral leading `.hierarchical` symbol (`checkmark.shield` / `shippingbox`
    / `clock`), `.subheadline` `content.secondary`, no action, no alarm styling.
  - **security banner** (`SecurityBanner`): pinned at the Bob-lane bottom, the most
    persistent element. `surface.card` with a hairline top separator, a leading
    `checkmark.shield`, `.subheadline .medium` text, and a single `.bordered` "Re-affirm
    your version" (`reaffirm_label`). Un-dismissable; no other affordance. Announces its
    persistent nature to VoiceOver.

- **Footer (borderless):** Preferences always; Set up when `setup-needed` + unmanaged.

#### 6.2.1 Join row + register row states (all 8)

**Join row (Region 3):** default = quiet `hollow` row + name + **Join**; hover / focus /
active = system states on the **Join** button only; disabled = Join dimmed with a `.help`
reason while offline or a sync is in flight; **loading (joining)** = the row label swaps
to an inline `ProgressView` + "Joining Sales" (named phase, no ETA), the button becomes
non-repeatable, and Region 1 shows `ring`; **error** = `not-entitled` becomes a plain
`content.secondary` line "This department is no longer available to you" (removed next
poll), `error` becomes "Could not join right now. Try again." with **Join** restored,
never a raw string; **empty** = the whole region is absent (structural), not a disabled
shell. On `joined` the row leaves Region 3 and the layer fills into Region 2 on the next
poll (the reward is the tree filling in, not a toast).

**Shared register row:** default = name + neutral "available" marker; hover / focus /
active / disabled / loading = **not applicable** (read-only, not a tab stop; a skeleton
row shows while the read resolves); **error** = an honest neutral "not available right
now" on the row (or "couldn't check your shared integrations" on the group), **never
green, never fabricated, never red / orange** (not the user's to fix); **empty** = the
Shared sub-group is **absent entirely**, not a blank.

**Personal register row:** default = name + state; hover / focus / active on the **Sign
in** button only; disabled = Sign in dimmed with reason while offline; loading = the S5
panel carries the pending state (the row is not the busy surface); error = the failure is
in the S5 panel's plain copy, the row returns to signed-out; empty = the Personal
sub-group is absent when the user has no personal integrations.

### 6.3 Wizard step shell + roadmap (S2): reuse Publisher, now 10 rows

`NavigationSplitView`: non-collapsible roadmap sidebar (`.sidebar` material, width 240 to
280) + content pane (`surface.window`, content col `maxWidth 600`) + pinned footer action
bar. Content anatomy every step: **eyebrow, title, intro, content region, footer** (Back
leading, ephemeral status center, primary trailing). Roadmap rows use the section 4.1
done / current / upcoming grammar; current row = `accent`@12% pill (radius 6) +
`circle.inset.filled`. The corrected roadmap has **10 rows**: Welcome, Detect, Choose,
Your layer, **Departments** (new, S11), Sign in, Set up, Verify, Learn, Ready. Completed
rows tappable (review, read-only); upcoming disabled. **No managed-silent lane** (S2b
removed, D4): every user reaches this one window.

The **Departments wizard step (S11)** and the **Sign in step (S5 sheet)** render with the
same grammar as their steady-state surfaces (7.3, 6.6): the departments list card and the
device-flow sheet. Each is skippable via a tertiary "Skip for now" so the wizard is never
a dead end (the popover Region 3 and the Bob lane carry the deferred item later).

### 6.4 Settings tabs (S3): native `Settings` scene (corrected: six tabs)

Standard tabbed Preferences: **General / Components & Layers / Integrations / Personal Key
Sync / Advanced / (conditional) Administration**. Tab icons: `gearshape` /
`square.stack.3d.up` / `app.connected.to.app.below.fill` (or `link`) / `key.icloud` /
`slider.horizontal.3` / `person.badge.key`.

- **Components & Layers:** the entitled-layer view (one row per component by layer with the
  same badge grammar as the popover tree), **plus the standing Department discovery / join
  panel (S11, 7.3)**. Managed org / dept rows render **locked** with a `lock` glyph +
  "Managed by your organization" (`.callout` `content.secondary`), fields disabled but
  VO-readable (`LayerRow.editable == false`); personal rows are editable. Errors show as
  plain `.callout` `danger` next to the field (never raw yaml / serde).
- **Integrations:** the **two separated registers** in the roomy window register: **Shared**
  (S12, a `building.2` section header "Shared" with the subtitle "Available because you're
  entitled", read-only rows, no sign-in) and **Personal** (a `person.crop.circle` section
  header "Your accounts", device-flow sign-in rows). Same structural split as the popover
  Region 4, at window scale. The separation is mandatory, not optional (D7.2).
- **Personal Key Sync (S13):** the new tab, specified in 6.5 and sketched in 7.4.
- **Advanced:** poll cadence, diagnostics; **no** security-sensitive re-pointing (no
  UpdateFeedURL / mirror / secret-store endpoint control).
- **Administration** renders **only when `admin_capable`** (Stage 1): absent, not disabled,
  when false.

### 6.5 Personal Key Sync tab (S13, new)

A single content pane (32 / 24 inset), `key.icloud` pane glyph, `.title` header "Personal
Key Sync". Three stacked blocks on `surface.window`:

- **The opt-in switch:** a native `.switch` (`Toggle`, `.switch` style) leading a two-line
  label: title "Sync my personal keys across my own Macs" (`.body .medium`
  `content.primary`) + honest scope line "Your keys, your machines only. Never shared,
  never in git." (`.callout` `content.secondary`). The switch is the CTA in the empty
  state (6.7). Enabling shows a brief in-progress state on the switch, then the roster
  updates; no ETA, no percentage.
- **Your machines roster** (a `surface.card` radius-10 group): one row per known machine =
  leading `laptopcomputer` / `desktopcomputer` (`.hierarchical` `content.secondary`) +
  machine name (`.body .medium`, "This Mac (name)" for the current device) + a neutral
  state marker ("Enrolled" `content.secondary` / "Not syncing" `content.tertiary`) + at
  most one trailing action: **Enroll** (`plus.circle`) or **Remove** (`minus.circle`).
  Rows are 32pt dense. **This Mac** never carries a Remove (you cannot un-enroll the device
  you are on from itself without turning the switch off). A skeleton loads the roster.
- **What syncs / What never syncs** (two labeled blocks, load-bearing reassurance copy):
  "WHAT SYNCS" (`.caption .semibold` uppercase `content.secondary`) over a plain
  `content.secondary` body naming personal integration keys; "WHAT NEVER SYNCS" over a body
  naming shared department integrations, the Git push key, and org-provided material. These
  are the structural boundary made legible; they are content, not decoration, and are read
  by VoiceOver as labeled groups.
- **Conflict chooser (when two of the user's Macs diverged a key):** a small inset card or
  sheet in the conflict-chooser grammar (6.7-style plain options): title "Two of your Macs
  have a different value for <account>. Which do you want to keep?" and **two radio options
  named by machine and by when the value was set** (for example "the owner's Mac Studio, set
  yesterday" vs "This Mac, set today"), a **Continue** that passes the choice to the
  carrier, and a safe park path. **The secret value is never displayed** (2.6 / section 9):
  the choice is by machine + recency only. Reuses the S7 plain-language, no-raw-material
  discipline for the user's own keys.

States (all 8) per Stage 2 section 4.6: default (switch + roster + blocks); hover / focus /
active on the switch, per-row Enroll / Remove, and conflict options; disabled (Enroll /
Remove disabled with reason while offline; whole tab disabled with an honest line if the
carrier is unavailable); loading (row-level in-progress on enroll / remove, skeleton
roster); error (plain "Couldn't change key sync right now. Try again.", a failed enroll
leaves the switch honestly off, never a raw carrier / keychain string); empty (sync off /
no other Macs: "Turn this on to stop copying keys between your Macs." with the switch as
the CTA).

### 6.6 Sheets & panels (reused verbatim)

- **Sign-in device-flow (S5, personal only):** wizard **sheet** or steady-state floating
  `NSPanel`. The `user_code` is the hero: large `.title2 .monospaced()` in a `surface.field`
  inset, `.textSelection(.enabled)`, with a `doc.on.doc` copy affordance ("Copied" fades). A
  `.borderedProminent` "Open Sign-in Page" (`arrow.up.forward.app`). Progress = an
  indeterminate "Waiting for you to finish in your browser" (`.callout` `content.secondary`),
  **no countdown, no timer, no token shown**. States authorized / denied / expired / timeout
  per Stage 2 with plain copy + Try again / Get a new code. **This is the personal register
  only; a Shared integration never routes here.**
- **Dirty-work panel (S6):** non-transient `NSPanel`; `folder` glyph + `BobPrompt.detail`
  (`.body`) + one respectful `action_label` primary. No discard-my-work control exists.
- **Conflict chooser (S7, author only):** modal sheet, radio-style options in plain
  sentences (Keep yours / Keep theirs / **Keep both** [pre-selected, recommended] / Park and
  ask an author). **Never `<<<<<<< HEAD`, never a raw diff.** Continue returns the choice;
  Park is the safe Esc exit.

### 6.7 Empty states (reused, corrected: no Fleet)

Every data-backed surface: a `content.tertiary` symbol + one-line explanation + benefit +
a single CTA where one exists. **Corrected set** (Stage 2 section 6.2): Departments (none
entitled) = "No departments are available to you yet." + a plain line that new departments
appear here when you're added to one, no CTA; Shared integrations (none) = the region is
**absent**; Personal Key Sync (off / no other Macs) = "Turn this on to stop copying keys
between your Macs." + the switch; Seed generator (first author), Team grant (no grants),
Preflight (never run) per Admin (6.8). The **Bob-lane empty state is the absence of the
region** (silence). "What changed" empty = "Nothing has changed since you last looked."
**The Fleet empty state is deleted** (no Fleet surface).

### 6.8 Admin window (S4): two-section source list (corrected, no MDM, no fleet-as-center)

One `Window`, left source-list sidebar in **two** static sections (**Onboarding /
Governance**), detail pane on `surface.window`. The prior three-section (Onboarding / Fleet /
Governance) sidebar is corrected: **there is no Fleet section as a center of gravity** (D4;
`FleetView` DTOs deferred, owner-gated).

- **Handoff header:** persistent read-only banner atop the window when Onboarding is active.
  `surface.card`, radius 10, a leading `arrow.left.arrow.right`, and the
  `{publisher, admin, artifact_ref, next_owner}` object as inline chips (`.callout`, radius-6
  chips): "Publisher: done · Artifact v1.4.2 · Next: you". When `next_owner` is the admin,
  subtly emphasize the current onboarding step (accent pill). No fill bar.
- **Onboarding sidebar items** (each with the section 4.1 done / current / upcoming mark):
  Prerequisites & contacts, GitHub topology, Authors & keys, Central shared secret store,
  Seed generator, Policy signers, Preflight. **Team access & entitlement (6.8 below)** renders
  within the per-department context of topology / authors.
- **Governance sidebar items:** Deprovision (by revocation), Analytics (opt-in), Secret-store
  config (read-only render of the inherited endpoint).
- **Seed-generator form:** sectioned cards (Components / Departments / Version pins / Auth
  references / Policy signers / Telemetry), each `surface.card` radius 10 with add / remove
  rows; native constrained controls (pickers, typed fields). The **Components** section names
  the four CSE components, never products. A **live read-only preview** card renders the
  assembled result as a human-readable structured summary in `surface.field` (not raw YAML).
  **Validate** shows per-field plain `FieldError` lines (`danger` `.callout` under the field) +
  a summary count. **Open Pull Request** = `.borderedProminent`, enabled only when valid;
  success = calm "Opened pull request <ref>" + Reveal link. Empty state per 6.7.
- **Central shared secret-store setup** (replaces the deleted managed-key collector): a short
  guided form on `surface.card`, store-type picker + an **endpoint URL** field (a URL, not a
  secret; validated as a URL inline on blur) + a **team-chooser** mapping GitHub teams to store
  scopes. **The secret-shape refusal is retained as a hard constraint** and is the load-bearing
  safety interaction: any field runs a fail-closed secret-shape check; a value that looks like a
  secret is rejected inline with a firmer-but-plain error, a `hand.raised.fill` (`.systemRed`) +
  "This looks like a secret. This setting never holds secrets; secrets live in the store itself
  or the keychain." The value is blocked, not stored, never echoed to logs. Output becomes part
  of the inherited org config the seed / PR carries (the app opens a PR, never writes managed
  config locally).
- **Team access & entitlement** (the entitlement spine as a surface, D3): a per-department view
  = the department's repo + team + the **grant**, rendered as plain-language entitlement, not an
  abstract permission: "People on this team can join the Sales department" (read) and "These
  people can author the Sales layer" (write). An add control opens a PR / calls the grant path
  via the author's own credential. `person.2.badge.key.fill` glyph. This is the visible other
  end of the user's S11 "Available to join" row. No secret ever appears here (a grant is repo
  access, not a credential). Empty = "No one can join this department yet. Grant a team read
  access to let them in." + an add CTA.
- **Preflight red / green rows:** one row per check = section 4.1 status mark (shape + color +
  text) + check name (`.body`) + one-line `detail` + an **owner chip** (Publisher / Admin /
  User, radius-6). `pass` = `checkmark.circle.fill` green + "Ready"; `fail` = `xmark.circle.fill`
  red + detail; **`unknown` = `questionmark.circle` orange + "Not checked", never green**. Header
  summary = plain count ("2 must be fixed, 1 could not be checked"), **never a score, ring, or
  gauge**. Red rows expand to a fix affordance routed to the owner (Admin-owned: jump to the
  relevant onboarding step with the offending field focused). Progressive fill while running;
  per-check `ProgressView`, no global ETA. Checks now cover the corrected spine (repos, teams /
  entitlement, secret store reachable, seed parses, pins resolve, policy signed), not MDM /
  managed-key checks.
- **Governance: Deprovision-by-revocation (S8):** the full `DeprovisionView` panel, a render of
  a **GitHub-access-revocation + secret-store token-rotation** event (no MDM wipe, no remote
  device wipe). `retained_dirty` prominent (the never-destroy reassurance), `secrets_touched`
  must be 0, `secrets_alarm` honest (the one deprovision case allowed to read as an alarm, orange
  or red, because honesty outranks calm), `unreadable` renders an honest holding, never a
  fabricated success. The app **never triggers** it; it renders the server-performed event.

**Deleted from the prior Admin surface (draw nothing):** the MDM profile generator, the 19
`MANAGED_KEYS` managed-key collector, the MDM upload walkthrough, and the entire **Fleet**
section (host list, actionable-items feed). No per-host dashboard, no fleet score, no fleet
empty state.

### 6.9 Notifications (reused)

`UNNotification` for the two Bob prompts (dirty-wip, and steady-state sign-in trigger),
system-styled (no custom chrome). Title = `BobPrompt.title`. When notifications are denied, the
prompt re-hosts in the popover Bob lane with an honest "Shown here because notifications are
turned off" note (`.caption` `content.tertiary`) above the live prompt.

---

## 7. Per-key-screen visual direction

Concrete layout + material + type + symbol + state color, building on Stage 2's interaction
layout. ASCII shows structure; the prose specifies the visual layer. Sketches cover the five
requested key screens: the popover (Healthy, entitled-not-synced / Join available,
cli-unreadable / bang), the department-join panel, the shared-versus-personal integrations
screen, personal-key sync, and one Admin onboarding screen.

### 7.1 Popover: Healthy (silence), and the corrected component tree

Material `.popover`; Regions 1 to 2 only; ~120pt tall.
```
+-----------------------------------------------+   .popover material
| [aviator glyph, bare]  Everything is set up.  |   sentence: .headline, content.primary
|                        This Mac               |   glyph: template, NO badge (none)
| --------------------------------------------- |   host: .subheadline, content.secondary
| > Claude Copilot                        *     |   component name .body; worst-wins pass dot
| > CLI Copilot                           *     |   dots (.systemGreen) are the ONLY color
| > Codex Copilot                         *     |
| > Knowledge Copilot                     *     |
+-----------------------------------------------+
  Preferences...                                    (footer, borderless, content.secondary)
```
Disclosed, a component shows its four entitled-layer cells:
```
| v CLI Copilot                           *     |   worst-wins pass dot
|      foundation                         *     |   layer cell .subheadline content.secondary
|      org                                *     |
|      department                         o     |   hollow ring = entitled, not synced
|      personal                           *     |
```
Visual note: no green fill, no checkmark reward, no "All good". The `pass` dots are the
quietest possible confirmation; a `hollow` ring on the department cell reads as an open
invitation, not a fault (and it drives a Region 3 Join row, 7.2). A not-entitled cell would
render dimmed `content.tertiary` with "You are not in this layer", shown but never faked green.

### 7.2 Popover: entitled-not-synced / Join available (the quiet invitation)

```
+-----------------------------------------------+   .popover material
| [glyph, bare]  Everything on this Mac is set  |   NOT an alarm; the tray stays bare
|                up. This Mac                    |   (entitled-not-synced does not badge tray)
| --------------------------------------------- |
| > Claude Copilot                        *     |
| > CLI Copilot                           *     |
| --------------------------------------------- |
| AVAILABLE TO JOIN                             |   .caption .semibold uppercase, content.secondary
|  o  Sales                          [ Join ]   |   hollow ring (content.secondary) + name .body
+-----------------------------------------------+   Join = native .bordered, right-aligned
  Preferences...
```
Visual note: the Join row is deliberately calm, `hollow` neutral gray, no bright "new!" badge,
no green. Joining swaps the name to an inline `ProgressView` + "Joining Sales" and Region 1 goes
to `ring`; on success the row leaves and Sales appears as a new department cell of currency in the
tree (7.1). The reward is the tree filling in, not a toast (Stage 2 section 2.5).

### 7.3 Department-join panel (standing list, Settings and wizard)

Roomy window register (`surface.card` radius 10). The wizard step and the Settings panel share
this exact layout.
```
  Departments you can join
  +---------------------------------------------------------+   surface.card, radius 10
  |  o  Sales           Available to join        [ Join ]   |   hollow ring; Join = .bordered
  |  *  Engineering     Joined                              |   neutral dot; read-only, no action
  |     Marketing       Not available to you                |   content.tertiary; no mark, no action
  +---------------------------------------------------------+
```
Visual note: three visually distinct row registers carry the three honest states before color.
**Available to join** = `hollow` ring (`content.secondary`) + a **Join** button (the only tab
stop / touch target in the row). **Joined** = a quiet neutral `circle.fill` `content.secondary` +
"Joined", read-only, no celebratory mark. **Not available to you** = `content.tertiary` text, no
mark, no action, and only where the CLI returns such a row (the app never invents a not-entitled
row to tempt, never offers "request access"). Skeleton rows while `copilot layers` resolves; the
whole-read failure renders "Couldn't check your departments right now. Try again." with a Retry,
never fabricated rows. Empty = "No departments are available to you yet." (6.7).

### 7.4 Shared-versus-personal integrations (the key visual move, at a glance)

Popover Region 4 (compact) and Settings Integrations (roomy) render the same two-register grammar.
```
+-----------------------------------------------+
| [building.2]  SHARED                          |   register icon + .caption .semibold uppercase
|               Available because you're        |   subtitle .caption content.tertiary
|               entitled                        |
|      Salesforce                   * available |   neutral dot (content.secondary), NO button
|      Workday                      * available |   read-only, not a tab stop
| --------------------------------------------- |   hairline separator + 12pt gap
| [person.crop.circle]  PERSONAL                |   register icon + label
|               Your accounts                   |   subtitle
|      Slack           [key] needs sign-in      |   key.fill .systemBlue mark
|                                  [ Sign in ]  |   native .bordered, opens S5 panel
+-----------------------------------------------+
```
Visual note (the distinction is structural, not a color choice): the **Shared** group is a
`building.2` group whose rows carry **neutral-gray state markers and zero buttons**; the
**Personal** group is a `person.crop.circle` group whose rows carry **blue `key` marks and Sign in
buttons**. Register icon + the presence-or-absence of a blue affordance encodes "just there because
I'm entitled" versus "I signed in myself" before any color is read, and the two group labels state
the reason in words ("Available because you're entitled" versus "Your accounts"). A Shared row that
cannot resolve shows a neutral hollow marker + "not available right now" (never green, never red /
orange; it routes to IT, not the user). The single most important fact here is a **negative** one:
the Shared register has no sign-in affordance, ever, and its rows are not tab stops. That absence
is the design (D7.2).

### 7.5 Personal-key multi-machine sync (S13, Settings tab)

Roomy window register.
```
  [key.icloud]  Personal Key Sync
  +-----------------------------------------------------------+
  |  (o ) Sync my personal keys across my own Macs            |   native .switch
  |       Your keys, your machines only. Never shared,        |   scope line .callout content.secondary
  |       never in git.                                       |
  +-----------------------------------------------------------+
  Your machines
  +-----------------------------------------------------------+   surface.card, radius 10, 32pt rows
  |  [laptopcomputer]  This Mac (the owner's MacBook Pro)         |   Enrolled  (no Remove on This Mac)
  |  [desktopcomputer] the owner's Mac Studio        Enrolled  (-) |   Remove = minus.circle
  |  [laptopcomputer]  the owner's old MacBook Air   Not syncing(+)|   Enroll = plus.circle
  +-----------------------------------------------------------+
  WHAT SYNCS
    Your personal integration keys (the accounts you signed
    into yourself).
  WHAT NEVER SYNCS
    Shared department integrations, your Git push key, and
    anything your organization provides.
```
Visual note: the switch is the hero and the empty-state CTA. The roster names each machine with a
device glyph and a neutral "Enrolled" / "Not syncing" marker (no green reward). The what-syncs /
what-never blocks are load-bearing reassurance copy, not decoration: they make the structural
boundary legible. The **conflict chooser never shows the secret value**: it names the two Macs and
when each set the value ("the owner's Mac Studio, set yesterday" versus "This Mac, set today") and asks
which to keep, reusing the plain-option conflict grammar. Remove of a machine other than This Mac
gets a confirmation (it changes another device's future behavior); everything else is directly
reversible.

### 7.6 Admin onboarding: Preflight (red / green, no score)

```
+-------------------------- Administration -------------------------+
| <-> Publisher: done · Artifact v1.4.2 · Next: Admin (you)         |   handoff banner, surface.card
+------------------+------------------------------------------------+
| ONBOARDING       |  Preflight                                     |   title: .title
|  Prerequisites   |  2 must be fixed, 1 could not be checked        |   plain COUNT, never a score
|  GitHub topology |  +-------------------------------------------+  |
|  Authors & keys  |  | (v) Seed parses          Ready     [Admin]|  |   green check + owner chip
|  Secret store    |  | (x) Update feed reachable <detail> [Admin]|  |   red x + plain detail
|  Seed generator  |  | (?) Secret store reachable Not checked[Adm]| |   orange ?, NEVER green
|  Policy signers  |  | (v) Teams granted        Ready     [Admin]|  |
|  * Preflight     |  +-------------------------------------------+  |
| GOVERNANCE       |                            [ Run preflight ]    |   .borderedProminent
|  Deprovision     |                                                |
|  Analytics       |                                                |
|  Secret store    |                                                |
|  config          |                                                |
+------------------+------------------------------------------------+
```
Visual note: two sidebar sections only (Onboarding, Governance); no Fleet section. Each preflight
row is shape + color + text + owner-chip; `unknown` uses `questionmark.circle` `.systemOrange` and
the words "Not checked" so it can never be mistaken for pass. Red rows expand to an owner-appropriate
fix affordance (Admin-owned rows jump to the relevant onboarding step). Dense rows at 32pt. No
aggregate gauge, ring, or percentage anywhere. The Central shared secret store and Team access &
entitlement surfaces (6.8) render in the same window with the same card grammar; the secret-store
form carries the fail-closed secret-shape refusal as its load-bearing safety interaction.

---

## 8. Motion (minimal, native, Reduce-Motion-safe) (reused verbatim)

Motion tokens reconcile the CSS `--motion-*` values; ease-out to enter, ease-in to exit,
ease-in-out to reposition. **No motion is load-bearing:** every animated state is fully legible
frozen (the shape carries it).

| Interaction | Treatment | Token | Reduce Motion |
|---|---|---|---|
| Glyph `hollow` (setup-needed) | slow opacity / scale **pulse**, 2s ease-in-out | `pulse` 2s | **static** hollow ring (`circle`) |
| Glyph `ring` (syncing) | rotate `arrow.triangle.2.circlepath`, 1.2s linear | `ring` 1.2s | **static** circular-arrows mark |
| Glyph `spinner` (updating-app) | native indeterminate `ProgressView` | native | **static** `square.and.arrow.down` |
| Popover disclosure | triangle rotate 90 deg + rows slide in, 180ms ease-out | `calm` 180ms | **cross-fade**, no slide |
| Join row joining / enroll row | label to inline `ProgressView`, 150ms cross-fade | `fast` 150ms | cross-fade only |
| Wizard step to step | cross-fade + 8pt trailing slide, 200ms ease-out | `calm` / `normal` | cross-fade only |
| Roadmap marker advancing | pill + glyph move, 250ms ease-in-out | `slow` 240ms | move without spring |
| Verify detect to result | cross-fade 200ms; result glyph subtle spring scale-in | `calm` | cross-fade, no spring |
| Field error appears | caption to error fade 150ms, **no shake** | `fast` 120ms | fade only |
| Copy confirmation ("Copied") | fade in 150ms, fade out after ~2s | `fast` / `calm` | same (opacity only) |

The three tray motions (`pulse`, `ring`, `spinner`) each have a **distinct static shape** so a
Reduce-Motion user still distinguishes setup-needed versus syncing versus updating-app with no
animation at all. No looping motion exists anywhere else.

---

## 9. Accessibility (reused verbatim, extended for the new surfaces)

### 9.1 Contrast

All text uses system semantic label colors on system backgrounds / materials, so AA+ is
guaranteed and auto-adapting to Increase Contrast. Status text is always `content.primary` or
`content.secondary` (never colored text as the signal). Mono blocks (handoff, log, `user_code`,
repo URLs, seed preview) are `content.primary` on `surface.field`. Status **color** is never the
sole carrier, so it needs only to meet the decorative 3:1 for the pip, which every system color
clears against menu-bar and card backgrounds.

### 9.2 Dynamic Type

Semantic `Font` styles throughout (section 3); no `.system(size:)`. Titles / body get
`.fixedSize(vertical)` so they wrap not clip; popover width is fixed but height grows and scrolls
internally at XL sizes; wizard / Admin / Settings cards grow vertically. Verify layout at the
largest accessibility sizes, including the two integration registers, the departments list, and the
key-sync roster.

### 9.3 Color-independence proof (grayscale) (unchanged)

Strip all color: the 12 badges remain distinguishable by **silhouette + text label** alone.

| State | Grayscale silhouette | Text label (VoiceOver + inline) |
|---|---|---|
| Healthy | *(no badge)* | "Everything is set up" |
| setup-needed / entitled-not-synced | hollow ring | "setup needed" / "available to join" |
| it-config-incomplete | wrench | "waiting on IT setup" |
| waiting-for-network | clock | "waiting for network" |
| offline | cloud + slash | "offline" |
| syncing | two circular arrows | "syncing" |
| signed-out | key | "needs sign-in" |
| update-available | down-arrow in circle | "update available" |
| needs-attention | filled **triangle** | "needs attention" |
| updating-app | box + down-arrow / spinner | "updating Control Tower" |
| cli-unreadable | filled **circle** + `!` | "error, cannot read setup" |
| pass (row) | small solid dot | "ready" |

The new surfaces are proven color-independent by structure + text, not color: the **Shared** versus
**Personal** registers are distinguished by their group icon (`building.2` versus
`person.crop.circle`), their group label ("Available because you're entitled" versus "Your
accounts"), and the presence-or-absence of a Sign in button, never by color. The departments list
distinguishes joinable / joined / not-available by shape (hollow ring / neutral dot / no mark) +
the words "Available to join" / "Joined" / "Not available to you". Triangle versus circle
distinguishes the two "!" states; three distinct arrow / box shapes distinguish the three motion
states. Every tree, list, and roster row prints the status **word**.

### 9.4 VoiceOver labeling (extended)

- Badges / dots / glyph: `accessibilityLabel` = the **state name**, never the SF Symbol name
  ("key" is "needs sign-in"; `bang` is "error, cannot read setup"; the tray also announces "a
  department is available to join" when a Join row exists).
- Component tree rows: "component name, status name" ("CLI Copilot, needs sign-in"); layer cells
  nested "layer name, status name, detail"; a not-entitled cell announces "layer name, you are not
  in this layer".
- Join rows: announced as an action, "Sales department, available to join, button"; the joining
  state is a polite live region ("Joining Sales").
- Integration registers: two labeled groups. The **Shared** group announces "Shared integrations,
  available because you're entitled" and **announces that it has no actions** so a VO user does not
  hunt for a sign-in button that does not exist; its rows are read-only values ("Salesforce,
  available"). The **Personal** group announces "Your accounts" and its rows carry the Sign-in
  action ("Slack, needs sign-in, button").
- Personal Key Sync: the switch announces its state; each machine row announces "machine name,
  enrolled / not syncing, and its action"; the what-syncs and what-never blocks are read as labeled
  groups; the conflict chooser names machines and recency, **never the secret value**.
- Admin: preflight rows announce "check name, status, owner"; the handoff header is a container
  announced on window open; the secret-shape refusal is announced firmly.
- Live regions (polite): popover status sentence, wizard phase label, join-row joining state,
  enroll-row state, update line, so changes announce without stealing focus.
- Groups: the roadmap, the Bob lane, the two integration registers, the departments list, the
  key-sync roster, the handoff header, and each form section are accessibility containers with
  descriptive labels.
- Copyable values (`user_code`, machine id, artifact ref, handoff block, PR ref, repo URL) are
  selectable and readable; copy buttons labeled by what they copy. **Secret values are never
  rendered** and so never announced.
- Focus ring is the system ring, never restyled; initial focus is set per surface; modal sheets
  trap focus, modeless panels do not steal it.

---

## 10. Implementation implications (handoff)

- **Tokens** versus `src/styles/*.css`: retire the web hex ramp; adopt system semantic colors
  (section 2). Keep the token *names* as a SwiftUI `enum` / asset-catalog mapping
  (`content.primary` to `Color(nsColor: .labelColor)`, etc.). Card radius standardizes to **10**;
  **popover width to 360** (six regions); status ramp stays gray-dominant + one blue + one orange +
  one red + one green-dot. The Shared integration register carries **no ramp color** (neutral
  markers only).
- **Assets:** one brand-glyph SVG rasterized at build time to a **template** menu-bar image (@1x /
  2x / 3x, ~18pt) plus a full-color brand mark for About. Twelve badge composites (base glyph +
  corner badge) or a runtime compositor that overlays the section 4 SF Symbol badge. The
  entitled-not-synced state uses the existing `hollow` badge (no new asset).
- **Components to build:** template `NSStatusItem` glyph with per-`BadgeState` badge + Reduce-Motion
  static variants; `NSPopover` **six-region** stack (header, component-by-entitled-layer tree,
  Join-available, the two integration registers, action row, Bob lane); the shared Publisher
  `NavigationSplitView` roadmap shell (reused for the wizard's **10 rows** + Admin); tabbed
  `Settings` scene with the **six tabs** (General, Components & Layers with the S11 panel,
  Integrations with the S12 / S5 split, Personal Key Sync S13, Advanced, conditional Administration);
  Admin `Window` (**two-section** source list: Onboarding, Governance, + handoff banner + seed form +
  secret-store setup + team-grant + preflight rows); floating `NSPanel`s (personal sign-in,
  dirty-work); modal sheets (wizard sign-in, conflict, key-sync conflict).
- **New parsed facts the visuals depend on (TA / CLI):** `copilot layers` / `layers join` payloads
  (S11), the shared-integrations read distinguishing shared-entitled-no-signin from personal-device-
  flow (S12), the personal-key-sync roster / status / conflict read (S13), the `admin_capable` fact,
  and the handoff object. The `ProductView.product -> component` rename (D2). Until a read lands, the
  region renders **nothing** (fail-to-silence), never a fabricated value.
- **Removed / deferred visuals:** MDM profile generator, managed-key collector, MDM upload, and the
  Fleet section (host list, actionable-items feed, fleet empty state, any fleet count / score) draw
  nothing. `DeptProjectView` nesting removed (no project inside a layer).
- **Motion:** three tray animations (`pulse` / `ring` / `spinner`) each with a distinct static
  Reduce-Motion shape; join / enroll transitions and everything else cross-fade under Reduce Motion.
- **Guardrails the visuals must not break:** no navy fill / bar / banner (navy only as template tint
  + About mark); the `none` / Healthy glyph is bare (no badge, no green); entitled-not-synced renders
  as `hollow` neutral, never green and never an alarm, and does not badge the tray; the Shared
  integration register has **no sign-in affordance, ever**, and no ramp color; `unknown` preflight is
  never green; no score / ring / sparkline / fleet gauge; no ETA / countdown; every status carries
  shape + text before color; no secret value is ever rendered (the key-sync conflict names machines +
  recency); no raw error / yaml / git / signature string ever reaches a surface (render only the
  DTO's guaranteed-plain fields).

---

*Stage 3 complete, on the corrected CSE domain. The visual language ("Quiet Instrument", the
color / status ramp, the brand-navy discipline, materials, the SF Pro type scale, the 12 shape-first
badge tokens, spacing / radii / elevation, motion + Reduce Motion, accessibility + grayscale proof,
and the Publisher Setup family coherence) is reused verbatim; the per-screen direction is
re-authored for the component-by-entitled-layer tree, the department-join surface (S11), the
shared-versus-personal integration split (S12 versus S5), the personal-key multi-machine sync (S13),
and an Admin mode of Onboarding + Governance with no MDM and no fleet-as-center (S4). Route to the
implementer (uid) for the SwiftUI build of the glyph / popover family, the shared roadmap shell, and
the Admin surfaces; and to cw for final microcopy of the placeholder strings (status sentences, the
join-available line, the two integration-register labels, the personal-key what-syncs / what-never
blocks, the secret-shape refusal, the bang variants). The visual contract, token system, badge
mapping, and per-screen direction are defined here and are consistent with Stage 1, Stage 2, SOUL,
and `publisher-setup-visual-spec.md`.*

## Sources
- [Apple HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Apple HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [NSStatusItem, Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [SF Symbols, Apple Developer](https://developer.apple.com/sf-symbols/)
