# User Setup feedback — UI direction

> Task: `TASK-179`
>
> Stage: UI design
>
> UX specification: `user-setup-feedback-uxd-spec.md`

## Direction

**Quiet Instrument, with an earned finish.**

The revised journey remains a first-party macOS utility: system materials,
semantic colors, SF Pro, native controls, flat cards, and shape-first state.
The finish feels important because the hierarchy resolves and the next action
is obvious, not because the interface becomes decorative.

This direction follows the canonical
`docs/03-design/control-tower-visual-system.md`. Where the older
`docs/product-design/04-experience-design/60-ui-design.md` differs, the newer
visual system governs:

- no brand-purple header band;
- system accent, never brand navy, for primary controls;
- cards have no authored shadows;
- the aviators silhouette is the status-item identity;
- no celebratory Healthy treatment.

## Window and shell

- Native SwiftUI/AppKit window, ideal **920 × 700pt**, minimum **800 × 600pt**.
- Non-collapsible roadmap sidebar, ideal **250pt**, using sidebar material.
- Content pane uses `.windowBackgroundColor`.
- Content inset: **32pt horizontal / 24pt vertical**.
- Readable column: **600pt max width**, leading aligned.
- Pinned footer: Back/secondary actions leading; primary action trailing.
- Revised roadmap has **9 rows**. Completed rows use a small green
  `checkmark.circle.fill`, current uses system accent
  `circle.inset.filled`, upcoming uses a tertiary hollow circle.

## Type hierarchy

Use semantic fonts only:

| Role | SwiftUI |
|---|---|
| Step title | `.title.weight(.semibold)` |
| Completion title | `.largeTitle.weight(.semibold)` when space permits; `.title` at large accessibility sizes |
| Intro/body | `.body`, secondary label |
| Inventory summary | `.callout.weight(.semibold)`, primary label |
| Card label | `.caption.weight(.semibold).textCase(.uppercase)`, secondary label |
| Row name | `.body.weight(.medium)`, primary label |
| Row explanation | `.caption`, secondary label |
| Supporting hint | `.caption`, tertiary label |
| Machine/provider token | semantic body; monospaced only for a code, never for a provider or project name |

The full project summary is one readable sentence, not a dashboard of statistic
tiles. The person should understand the inventory before their eye reaches a
checkbox.

## Color roles

Use system semantic colors in the native implementation.

| Meaning | Native role | Use |
|---|---|---|
| Primary content | `.labelColor` | Titles, row names, verified facts |
| Secondary content | `.secondaryLabelColor` | Explanations, ready state |
| Tertiary content | `.tertiaryLabelColor` | Hints, unavailable-with-no-action |
| Action | `.controlAccentColor` | Primary button, current roadmap row, link actions |
| Verified row | `.systemGreen` | Small row-level pass dot/check only |
| User-actionable hold | `.systemBlue` | Sign-in/key action |
| Recoverable project problem | `.systemOrange` | Triangle plus plain reason |
| Unreadable/systemic boundary | `.systemRed` | Filled bang only; never a field or banner fill |

Successful connection rows use a neutral `circle.fill` and the word **Ready**,
not a green check. Green appears only where a verification result has actually
passed.

## Spacing, geometry, and materials

- 8pt grid: **4 / 8 / 12 / 16 / 24 / 32**.
- Cards: `.controlBackgroundColor`, **10pt continuous radius**, 16pt padding.
- Card-to-card gap: 16pt; major section gap: 24pt.
- Rows: at least 44pt effective hit area when interactive; read-only rows keep
  native density.
- Dividers: `.separatorColor`, inset to align with row content.
- Buttons and checkboxes retain native styling and system focus rings.
- No custom card shadow. The walkthrough uses a window shadow only to simulate
  the macOS window layer.

## Connections

### Ready to use

- Card label in uppercase caption.
- Each row: neutral status dot, provider name, reason/source, trailing word
  **Ready**.
- Organization-provided and personally connected rows share geometry; the
  source sentence distinguishes them.

### Available to connect

- Separate card rendered only when rows exist.
- Leading `key.fill` in system blue.
- Trailing native bordered **Connect [Provider]**.
- The action is the only blue element inside the row.

### Loading, empty, unreadable

- Loading: still skeleton bars on `.controlBackgroundColor`; no shimmer.
- Successful empty: one quiet empty-state card, no symbol larger than body
  scale.
- Unreadable: `exclamationmark.circle.fill` red plus the exact sentence;
  **Try again** is bordered, **Continue and check later** is plain.
- These states never share a visual treatment.

## Projects

- Summary and instruction are above the first card.
- **Available to set up** card header carries a quiet selected-count label and
  plain text actions **Select all available / Clear selection**.
- Native checkboxes lead each eligible row.
- **Already set up** is a collapsed disclosure card.
- **Can't be set up here** uses:
  - neutral `minus.circle` when no action is required;
  - orange `exclamationmark.triangle` when the user can recover;
  - blue bordered action only when the action belongs to the user.
- No blocked row is selectable.
- Primary button includes the selected count. Zero selection changes the
  primary label rather than leaving a disabled mystery.

## Setup progress and recovery

### Running

- Fixed title and intro.
- Honest count in callout semibold.
- A 6pt native-accent progress strip is permitted only because the numerator
  and denominator are both known named rows; it disappears when work ends.
- Row shapes:
  - hollow circle: not started;
  - accent inset circle + native spinner: working;
  - small green check: done;
  - orange triangle: could not finish;
  - red bang: unreadable/systemic.

### Partial failure

- The screen remains in the same shell.
- The summary title is primary text, not red.
- Successful rows collapse into a quiet evidence card.
- The failed row remains expanded in a normal card with:
  - orange triangle;
  - **Not set up** state word;
  - cause, preservation, and next action as three short blocks;
  - one primary recovery action.
- There is no tinted warning card background and no alert-style modal.

### Systemic project failure

- Red bang is earned only when the typed boundary cannot provide a valid
  project outcome or every failure shares a systemic error.
- The title remains plain primary text.
- **Check project setup** is primary; **Continue without projects** is plain.

## Verified completion

- Eyebrow: **SETUP VERIFIED**, system accent.
- Title: **Your copilots are ready**.
- No oversized checkmark, green field, illustration, confetti, or trophy.
- The first card, **Ready now**, uses small row-level green checks because each
  listed fact was verified.
- Optional **Still to do** uses neutral or orange shape based on the CLI's
  owner/action classification, never a blended warning banner.
- **What happens next** is a plain card with the supplied aviators glyph at
  20–24pt beside the menu-bar explanation.
- Primary: **Finish setup**.
- Secondary: **Show what setup did**.
- Tertiary learning link: **See what you can build**.

Finishing may open the popover once. The transition is a 200ms cross-fade;
Reduce Motion swaps instantly.

## Aviators family

The status-item base is always rasterized from
`src-tauri/icons/aviators.svg`, approximately 16–18pt high in the menu bar.

- Healthy: template aviators, no badge.
- Syncing: aviators plus ring.
- Sign-in: aviators plus key.
- Waiting/offline: aviators plus clock/cloud-slash.
- Attention: aviators plus triangle.
- Unreadable: aviators plus bang.

Badge occupies approximately 8–9pt at the bottom-trailing corner. If color is
removed, shape plus the accessibility sentence still distinguishes every
state. The Control Tower illustration is never assigned to `NSStatusItem`.

## Motion

| Event | Motion | Reduce Motion |
|---|---|---|
| Step change | 200ms cross-fade + 8pt trailing slide | Cross-fade |
| Row resolves | 150ms shape/text cross-fade | Instant |
| Progress strip | 250ms width ease-out after real progress | Instant width |
| Browser authorization | Native spinner beside named provider | Static state text |
| Completion resolves | 200ms content cross-fade | Instant |
| Status badge | Existing token motion | Existing static shape |

No stagger, bounce, shimmer, confetti, or decorative looping motion.

## Responsive and accessibility

- At widths below 800pt, sidebar remains visible at its minimum while content
  wraps; the window does not turn into a mobile layout.
- At accessibility text sizes, the content column expands vertically and the
  body scrolls; the pinned footer remains reachable.
- Provider and project rows combine name, state, source/reason, and selection
  for VoiceOver.
- Failures announce immediately without moving focus.
- Completion focus moves to the title only after Verify resolves.
- Shape and text carry every state before color or motion.
- Contrast uses native semantic colors and Increase Contrast behavior.

## Implementation fidelity checklist for `$uid`

- Reuse `stepShell` and `sectionCard`; do not create a second shell.
- Replace static provider structs with typed render models before styling.
- Preserve native buttons, toggles, disclosure groups, and focus rings.
- Remove the tenth roadmap row only with state-machine and persistence tests.
- Add reusable connection row, project outcome row, result summary, and
  aviators explanation components.
- Keep error cause/action text data-driven.
- Capture matching light, dark, Increase Contrast, Reduce Motion, and large
  text screenshots for QA.
- Add source and real-pixel assertions for every status-item variant.
