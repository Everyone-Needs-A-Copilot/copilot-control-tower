---
name: Feature request
about: Propose new capability for Control Tower
title: "[Feature] "
labels: enhancement
assignees: ''
---

## Have you checked this against SOUL.md's Feature Filter?

**Read [`SOUL.md`](../../SOUL.md) Section 5 (Feature Filter) before filling
this in.** Many "obvious" additions — a chat surface, an offline health score,
`KeepAlive=true`, a `--force` bypass, a paid tier — are deliberate non-goals,
already rejected in writing with reasoning in SOUL.md's Case Law table.

- [ ] I have read SOUL.md §5 and the Case Law table
- [ ] I have checked this idea isn't already listed there as **OUT**
- [ ] I believe this passes all four gates below (explain how, per gate)

| Gate | Question | Your answer |
|---|---|---|
| 1. Parse-Not-Compute | Does this require the app to compute ecosystem state (resolve, score, verify, prune, wipe)? | |
| 2. Essential-Job | Does this serve the spine — giving a non-technical person a technical person's superpowers, without requiring technical skill? | |
| 3. Right-Actor | Is every prompt this creates routed to the sole competent actor for a reversible-or-owned decision? | |
| 4. Trust-Surface | Does this avoid drifting toward any named anti-pattern (The Second Pilot, The Alert Machine, The Convenience Backdoor, The Copilot of the Copilot, The Ledger That Learns to Bill, The Leak, The Git Error To A Non-Technical Person)? | |

## What problem does this solve?

Describe the struggling moment — who hits it, and what they can't currently
do.

## Proposed solution

What would Control Tower do differently? Be specific about what it *renders*
versus what the CLI would need to *compute* — if your proposal requires new
CLI-side logic, note that it may belong in the `copilot`/`claude-copilot` repo
instead of here.

## Alternatives considered

Did you consider whether this belongs in the CLI, in a different part of the
ecosystem, or not at all?

## Additional context

Anything else — mockups, related issues, prior discussion.
