# Resolve with Claude Code — UI Design Specification

Status: Phase 9.2 design handoff

Companion: `22-resolve-with-claude-code-uids-walkthrough.html`

## Direction

Continue **Quiet Instrument**. The one-button experience should feel like
handing a prepared batch to a visible specialist, then calmly reviewing its
work. Claude Code does not introduce a second brand palette, chat transcript,
terminal imitation, or celebratory assistant personality into Control Tower.

The visual sequence has three registers:

1. **Act** — one accented Resolve button on the existing default-all batch.
2. **Observe** — a neutral preparation card with real status and no fake meter.
3. **Decide and verify** — restrained proposal, owner-decision, held, exact-plan,
   and receipt groups using the existing state ramp.

## Hierarchy and layout

- Retain the native macOS title bar, setup rail, 820-point content cap, and
  existing Step 7 footer.
- The batch summary remains first. The prominent control becomes **Resolve N
  projects with Claude Code** with `sparkles` as a secondary glyph.
- Keep **Choose projects individually** and **Use standard setup only** as plain
  or bordered secondary actions. Neither competes with Resolve.
- Preparing replaces the selection body in place. It does not open a fake chat
  panel inside the app.
- Proposals-ready uses a compact three-part summary: ready to review, needs your
  decision, and left unchanged. Project lists sit below in disclosures.
- Owner decisions are full-width decision blocks, one project at a time.
- The exact plan and receipt reuse current reconciliation cards so the new flow
  converges visually with the proven transaction path.

## Existing tokens

- Spacing: `CTSpace.sm` 8, `md` 12, `lg` 16, `section` 24, `pane` 32.
- Radius: `CTRadius.card` 10; inset wells use `CTRadius.well` 8.
- Type: `CTType.eyebrow`, `stepTitle`, `lead`, `cardTitle`, `sectionTitle`,
  `rowTitle`, `rowDetail`, and `status`.
- Surfaces: `CTColor.page`, `card`, `well`, `cardBorder`, and `hairline`.
- State: actionable accent for Resolve and prepared proposals; attention for
  owner decisions; neutral for held work; ready only after independent
  verification; blocked only for unreadable truth or incomplete restoration.

Respect the person's macOS accent. Do not add Claude orange, a purple assistant
gradient, filled banners, or hard-coded brand color.

## Components

### Resolve action

A native prominent button with `sparkles` and an exact count. Minimum 44-point
target. The label, not the glyph, carries meaning. On narrow layouts the button
is full width and appears after the batch summary.

### Preparation card

Use one `CTCard` with a native indeterminate spinner, section title, current
service sentence, **Nothing is changing yet**, and a quiet **Stop preparing**
button. Completed preparation stages use checkmark shapes but remain neutral;
green is reserved for final verification. Never show a percentage without a
real bounded total.

### Proposal summary

Three compact rows, not dashboard tiles:

- arrow-right-circle, **N proposals ready to review**, actionable;
- person-crop-circle, **N need your decision**, attention;
- hand-raised, **N left unchanged**, neutral.

The first is visually primary. Counts and state words are always present, so
the summary survives grayscale.

### Owner decision block

Use `CTDecisionBlock` with project name, plain question, native radio group,
one-line effect text, and a collapsed **Why this is needed** disclosure. The
unanswered state has an attention rail, not red. Validation adds text below the
group and moves focus; it does not shake or flash.

### Held work

Use a neutral `CTCard` with `hand.raised` or `lock.shield`. Rows carry project
name, reason, and next action. No red fill, warning triangle, or disabled
checkbox. Held work is outside the selectable/apply surface.

### Permission and unavailable states

- Claude Code unavailable: neutral decision card with `terminal` plus slash,
  **Check again**, and standard-only fallback.
- Permission denied: attention decision block with `gearshape`, **Open System
  Settings**, and **Try again**.
- Incompatible or unreadable report: blocked `exclamationmark.circle.fill`, one
  honest compatibility sentence, and no Resolve action.

### Apply and receipt

Applying and fresh verification are separate neutral progress cards. The
receipt uses row geometry already established by reconciliation:

- checkmark circle + **Verified**;
- minus circle + **Left unchanged**;
- arrow-uturn-backward circle + **Restored**;
- exclamation circle + **Needs attention**.

Restored is attention/neutral, not red. Only incomplete restoration earns the
blocked ramp.

## Responsive, appearance, and motion

- At widths below 700 points, footer actions stack primary last in visual order
  but first in the default keyboard action.
- Decision choices stack vertically at every width; never compress into a
  horizontal matrix.
- Lists scroll in the content pane while the title and native footer remain
  reachable.
- Use semantic dynamic colors for light, dark, and Increase Contrast.
- Under Reduce Motion, replace progress-stage crossfades with immediate content
  changes and keep the spinner's text equivalent.
- At larger text sizes, counts and state labels wrap; project names never
  truncate the only decision context.

## Implementation handoff

The UI implementation should reuse `CTCard`, `CTStatusRow`, `CTDecisionBlock`,
`CTCalloutNote`, and native controls. It should add no assistant-specific design
system. Every screen needs deterministic visual fixtures for light, dark,
permission denied, unavailable, preparing, proposals ready, owner decision,
held work, verification, restored, and incomplete-restoration states.
