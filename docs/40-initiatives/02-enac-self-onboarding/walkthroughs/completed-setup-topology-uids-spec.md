# Completed Setup Topology — UI Specification

## Direction

Use the existing restrained macOS Control Tower system: native window material,
system typography, 12-point continuous cards, system colors, and quiet
evidence-bound status marks. The visual hierarchy is a setup console, not a
celebratory dashboard.

## Geometry

- Window target: 820 × 760, resizable down to 680 × 600.
- Page inset: 28 points.
- Section gap: 20 points.
- Card inset: 18 points.
- Component card gap: 10 points.
- Tier rows: a stable two-column label/status structure with details below.
- Project category cards: full-width buttons, 10-point radius, count aligned
  trailing.

## Type

- Page title: system large title, semibold.
- Status headline: title 2, semibold.
- Section titles: title 3, semibold.
- Component names: callout, semibold.
- Tier names and state: caption, semibold.
- Evidence and repository visibility: caption or caption 2, secondary label.

## State treatment

- Ready: checkmark circle and system green, used only where helper evidence
  exists.
- Needs setup: hollow circle or wrench plus label-color text; primary action is
  blue.
- Not joined: hollow circle and secondary text.
- Could not check: warning triangle and system orange.
- Loading: named progress row; card geometry remains stable.

## Product language

- Always say Foundation, Organization, Department, and Personal.
- Never label the Personal tier “Private.”
- Technical disclosure may say “Private GitHub repository.”
- Separate “Ready to use” from “Setup complete.”
- Project copy is identical to Step 7.

## Responsive behavior

Below 740 points, component cards remain one column and tier details wrap.
Project category buttons retain count and chevron alignment. No horizontal
scrolling is permitted.

## Fidelity requirement

Settings must route into the same Step 7 project category view; it must not
introduce a second list-row visual language or a generic “need review” section.
