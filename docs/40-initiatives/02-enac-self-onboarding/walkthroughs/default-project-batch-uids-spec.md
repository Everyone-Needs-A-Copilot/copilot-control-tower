# Default Project Batch — UI Design Specification

Status: implementation-approved from owner direction

Task: `tc` 241

Companion: `20-default-project-batch-uids-walkthrough.html`

## Direction

Continue Quiet Instrument: one calm decision, two explanatory counts, and a
single primary action. The screen should feel like accepting a prepared batch,
not administering a migration system.

## Layout

- Keep the existing setup rail and native window chrome.
- Use a content column capped near 820 points.
- Place the main batch checkbox in a lightly blue-tinted selection card.
- Place New setup and Needs correction in a two-column count row.
- Put the primary review button in the existing bottom action row.
- Render ready and needs-review acknowledgements as compact text rows below the
  counts, not dashboard cards.
- Individual mode replaces the batch card body; it does not open another window.

## Visual hierarchy

- The selected-project total is the dominant numeral.
- Category counts are one level quieter.
- Green is reserved for the ready acknowledgement and verified receipts.
- Blue indicates the current selection and primary action.
- Orange appears only when a prerequisite prevents proceeding.
- Needs-review projects use neutral protective language, not red failure styling.

## Components

### Batch selection card

One native checkbox, title, supporting sentence, and selected total. No product
logos or component badges appear because Claude plus Codex is universal.

### Summary pair

Each count has a short label and one sentence. The cards are not interactive;
they explain the selected batch.

### Individual project row

One checkbox, project name, and pill-like text label (**New setup** or
**Needs correction**). Rows have no disclosure, component switch, recipe menu,
or technical path. **Select all** and **Select none** use plain buttons above.

### Mac prerequisite

A ready Mac receives one compact check row. A blocked Mac receives one bordered
orange-tinted panel with a heading and one next action. Do not enumerate blocker
records.

## Responsive behavior

- Above 700 points, summary cards remain side by side.
- Below 700 points, they stack and the footer actions stack.
- Individual rows remain full-width with no horizontal scrolling.
- The selection list scrolls inside the content region while the footer remains
  reachable.

## Reduced motion and contrast

Use native controls and semantic system colors. No selection transition depends
on animation. Focus rings, checkbox state, text labels, and count changes remain
visible in light, dark, increased-contrast, and reduced-motion settings.
