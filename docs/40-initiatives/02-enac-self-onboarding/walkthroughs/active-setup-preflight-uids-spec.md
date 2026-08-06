# Active Setup Preflight — UI Direction

Companion: `26-active-setup-preflight-uids-walkthrough.html`

## Direction

Use the existing Quiet Instrument system. The new preflight is a transient
operator state and a compact receipt inside Step 7, not a new dashboard or
setup step.

## Hierarchy

1. One plain progress or outcome headline.
2. One sentence naming the complete bounded operation or ledger-backed result.
3. One existing section card with three ordered activities during work.
4. On completion, one receipt card followed by the existing project summary.
5. Exception rows appear after completed work and never visually erase it.

## Existing tokens and components

- Reuse `CTSpace`, `sectionCard`, native `Label`, native bordered buttons, and
  the current StepShell width and footer.
- Blue means current action/progress only. Green is reserved for a completed
  CLI-authored postcondition. Orange is reserved for a specific preserved hold,
  never the entire project census.
- Use `.headline`/`.callout`/`.caption` in the existing hierarchy. Do not add a
  new display type scale, progress percentage, animation, shadow, or badge.
- Keep card geometry stable while the three activity rows advance so the
  window does not jump.

## State presentation

- Working rows use one current progress indicator; completed rows become a
  check label; waiting rows remain secondary text.
- A successful receipt uses a normal card, not a celebratory banner.
- A partial result shows completed ledger rows first and preserved holds second.
- Download-only shared setup uses a neutral downward-arrow label. Author
  capability is diagnostic evidence, not a colorful entitlement badge.
- Reduced motion removes animated progress while retaining the status text.

## Responsive and accessibility

- At narrow widths, the row status falls below its description rather than
  truncating the project or action name.
- No horizontal project table is introduced.
- Every state has a text label; icons and color are redundant.
- Focus and announcements follow the UX specification.

## UID implementation notes

- Add a typed preparation state and render the CLI-authored ledger; do not
  synthesize counts from project arrays.
- Preserve the existing Step 7 container, disclosure groups, and footer.
- Use a fixed three-row progress composition and reuse the batch card for the
  fresh result.
- Never render raw GitHub permission values or ecosystem role tokens.

