# Soul — Copilot Control Tower

> **Status: DRAFT v0.1 — stub, pending ratification.**

This document is the product's **soul**: its essence and decision instrument — the north star a team checks a feature or trade-off against when the spec is silent. It is not the architecture (that's [`../01-architecture/architecture.md`](../01-architecture/architecture.md)) and not the PRD (that's [`../02-prd/prd.md`](../02-prd/prd.md)); it is the "why" underneath both.

## How this gets produced

A proper `soul.md` is the output of **Product Creation Copilot**'s Discovery → Design phases, not something written unilaterally after the fact. PCC's discovery conversation surfaces the product's essence, tensions, and non-negotiables and distills them into this file. Until that conversation runs, treat everything below as a working draft, not a ratified soul.

Local path: `/Volumes/Dev/Sites/COPILOT/product-creation-copilot`. Invoke by running `claude` in that repo and saying "Read quickstart.md and let's begin." Note: the systems architecture and engineering PRD for Control Tower are already done (see `01-architecture/` and `02-prd/`) — PCC's discovery here should be scoped to ratifying and sharpening the essence below, not re-deriving the architecture from scratch.

## Working essence (pre-ratification)

A control tower that gives anyone a working AI partner from one click, and keeps the whole fleet healthy — so an enterprise can adopt the Copilot ecosystem without friction.

Two beneficiaries, one instrument: Bob gets a partner that just works and never asks him to be technical. IT gets a fleet they can see, trust, and stand up without hand-editing YAML. The tension the soul must resolve is between those two — invisible for Bob, fully legible for IT — and the answer so far is the tower metaphor itself: it watches and coordinates, it does not fly the plane, and it never computes what the CLI already computes.

## Next step

Run the PCC Discovery conversation, feed it this draft plus `01-architecture/architecture.md` §1 and §9, and replace this file with the ratified output.
