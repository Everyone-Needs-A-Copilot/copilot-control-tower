# Fleet-guided reconciliation — UI specification

## Direction

Use the existing Quiet Instrument system. The assistant choice is a pair of
native actions, not a new AI-branded surface. The instruction package is a
supporting fact; independently verified progress remains visually dominant.

## Hierarchy

1. State eyebrow and plain-language heading.
2. One sentence describing what the user can do now.
3. One bordered batch/progress card with verified and remaining counts.
4. One primary assistant action and one secondary assistant action.
5. Tertiary file/copy/support actions.

## State treatment

- Preparing and active use the existing blue actionable role.
- Waiting for a conversation uses the existing attention role, not error red.
- Verified uses the ready role only after Python reports the pass.
- Terminal or schema failures use the existing blocked role with a concrete
  recovery action.
- Colour is always paired with a symbol and text.

## Layout

- Preserve the Step 7 split-view shell and its current minimum window size.
- Keep assistant buttons together in the footer on wide layouts and stack them
  at narrow widths.
- Keep counts stable when their digits change; avoid expanding project rows.
- Long root and instruction paths appear only in the disclosure/support area.

## Walkthrough

[24-fleet-guided-reconciliation-uids-walkthrough.html](24-fleet-guided-reconciliation-uids-walkthrough.html)

