# Truthful Setup and Recovery — UI Design Specification

Status: visual walkthrough
Task: `tc` 183
Companion: `06-truthful-setup-recovery-uids-walkthrough.html`

## Direction

Continue the established **Quiet Instrument** system. The interface should feel
like a precise macOS utility: composed, native, and legible. The finish is earned
through hierarchy and evidence, not confetti or saturated success panels.

## Visual principles

1. Facts before decoration.
2. Text and shape carry state before color.
3. Green is evidence-bound and small.
4. Orange marks a recoverable, user-owned action—not every unresolved item.
5. Owner-routed items remain neutral.
6. Red is reserved for unreadable or failed verification boundaries.
7. Healthy state is quiet.

## Window and structure

- Ideal setup window: 920 × 700 points.
- Corner radius: 16–18 points.
- Stage rail: 220–246 points.
- Main content padding: 32–38 points.
- Cards use one-pixel semantic borders with no authored shadows inside the app.
- The walkthrough may use a single window shadow to simulate macOS.

## Typography

- System stack: `-apple-system`, `BlinkMacSystemFont`, `SF Pro Text`,
  `Segoe UI`, sans-serif.
- Screen title: 28 points, semibold, tight tracking.
- Finish title: 34–36 points.
- Body: 14–15 points.
- Metadata and section labels: 11–12 points, semibold.
- Never use all caps for user-facing status sentences.

## Color tokens

Tokens are semantic and adapt to light/dark mode:

- `page`: walkthrough background
- `window`: app chrome
- `sidebar`: stage rail
- `surface`: cards
- `field`: quiet inset treatment
- `text`, `muted`, `faint`
- `line`
- `accent`
- `ok`
- `warn`
- `danger`

Color is supplemental. Every colored state has a glyph and text label.

## Components

### Copilot inventory row

- 28-point glyph or monogram.
- Copilot name and plain-language summary.
- Expandable layer rows: Foundation, Organization, named Department, Personal.
- Trailing text status.
- Layer rows show repository name, visible path, and plain-language action.
- Green means evidence is complete; blue means Control Tower can create or
  download; orange means update/preservation attention; red means blocked or
  unreadable. Every state also has an icon and text.
- Missing rows contain at most one primary setup action in the screen footer.

### Repository location

- A quiet folder card precedes the inventory.
- Show the full selected path with text selection enabled.
- Explain that new repositories appear beside existing ones.
- A secondary “Choose another folder…” button remains available.
- Never render a hidden mirror path as the person’s repository location.

### Project group

- Count and one-sentence definition in the header.
- Rows state existing copilot, safe addition, preservation, and actor.
- Ready groups collapse by default.
- Guided-integration rows use a route glyph and supported external action.
- Owner-handoff rows use a person glyph and neutral text.

The high-detail project state family is defined in
`08-project-integration-aftercare-uids-walkthrough.html`.

### Verification card

- Small check glyph.
- Evidence statement, never a vague “Nice.”
- “What happens next” card includes the supplied aviators mark.

### Menu-bar status

- Base silhouette is always the supplied aviators SVG.
- Healthy: no badge.
- Syncing, sign-in, waiting, attention, or unreadable states add a small
  bottom-trailing badge without replacing the mark.

## Motion

- Progress changes only when a named item completes.
- No looping celebratory animation.
- Reduced motion removes transitions and animated indicators.

## Walkthrough requirements

- Eleven numbered screens with a persistent table of contents.
- Previous/next links for linear review.
- Light, dark, and system theme control.
- Self-contained HTML with no external network requests.
- Screen annotations explain hierarchy, responsibility, and state treatment.
