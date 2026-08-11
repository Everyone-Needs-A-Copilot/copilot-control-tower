# User-controlled project handoff — UI specification

## Direction

Use the existing Quiet Instrument system. The work-order handoff is a short,
calm instruction card—not an AI-running surface. The only visually dominant
action after preparation is **Copy prompt**. Terminal and file actions are
secondary; fresh verification is separate.

## Hierarchy

1. State eyebrow and plain-language heading.
2. One sentence establishing that the person controls the assistant.
3. One bordered card with four numbered steps.
4. A compact monospaced prompt panel with **Copy prompt**.
5. Secondary actions: **Show Terminal**, **Open instruction file**, and **Check
   the projects**.

## State treatment

- Preparing uses the existing neutral activity treatment and lasts only while
  Python writes the package.
- Instructions ready uses the blue actionable role. It is not success green.
- Terminal opening failure uses the existing attention role and keeps the
  prompt visible.
- Final verification uses the neutral checking treatment.
- Remaining work uses attention, with per-project reasons from Python.
- Verified uses the ready role only after the fresh final check passes.
- Colour is always paired with a symbol and text.

## Layout

- Preserve the Step 7 split-view shell and minimum window size.
- Keep the numbered steps vertical and scannable; never compress them into a
  sentence.
- Clamp the visible prompt to a readable panel with selectable text and a Copy
  button. The full work order is opened as a file rather than rendered inline.
- Keep **Copy prompt** and **Show Terminal** together. Place **Check the
  projects** after a divider so it cannot look like part of starting the
  assistant.
- Long root and instruction paths appear only in support text or the file
  opener, never as the heading.
- At narrow widths, actions stack in reading order with the primary action
  first.

## Walkthrough

[24-fleet-guided-reconciliation-uids-walkthrough.html](24-fleet-guided-reconciliation-uids-walkthrough.html)

