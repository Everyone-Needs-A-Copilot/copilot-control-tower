# Phase 6 Outcome — satisfied by building the real product

> **Status — recorded 2026-08-03.** Describes **v0.4.0** (released 2026-08-02). This is the Phase 6 output for Copilot Control Tower. It is deliberately **not** one of the four template formats; this document records which route was taken and why, so a future reader does not mistake the absence of a Figma file or a Storybook project for unfinished work.

## What happened

Phase 6 exists to turn the design package into something tangible. For this product that already happened, by the most direct route available: **the product was built**. The output is a shipping, signed, notarized native macOS application — three executables compiled from ~22,650 lines of Swift, at v0.4.0, with eight version lines and seven retained signed releases behind it, running in production on a real organization at 16/16 live apply.

The design package was then **retrofitted** onto that product on 2026-08-02, because the documentation had drifted far enough from the shipping code to be actively misleading. That inversion — build first, document from evidence second — is why the phase closes differently than the template anticipates.

## Why none of the four template formats applies

The template offers Figma, Design Specification, Storybook, and Next.js prototype. Each was considered against a product that already ships.

| Format | Verdict |
|---|---|
| **Figma design** | Rejected. It would produce a visual mock of screens that already exist, render at real fidelity, and are already covered by the visual system of record. A picture of the thing is strictly less true than the thing |
| **Storybook** | Rejected. Storybook is a web component-library tool. This is a native SwiftUI/AppKit application; there are no web components to catalogue, and standing up a Node project to describe a Swift app would add a build surface serving nothing |
| **Next.js prototype** | Rejected for the same reason, more strongly. A clickable web approximation of a signed native menu-bar app would be a lower-fidelity imitation of a real product, and anyone testing against it would be testing the wrong thing |
| **Design specification** | Considered seriously, and rejected on the product's own principle. Its content — tokens, components, screen specs, interaction patterns — already exists in [`../04-experience-design/60-ui-design.md`](../04-experience-design/60-ui-design.md), [`../04-experience-design/50-ux-design.md`](../04-experience-design/50-ux-design.md), and the native design triad. Writing a consolidating spec would create a fourth copy of the same truth, and the central finding of the 2026-08-02 audit is that duplicated documentation drifts and then lies. `SOUL.md` §3 Principle 5 — *as little app as possible*, and by extension as little surface as possible — rejects exactly this: a new artifact that adds maintenance burden without serving the essential job |

The decision was put to the owner on 2026-08-03 and this route was chosen explicitly.

## The design of record

There **is** a full design specification for this product. It is not in this folder, because it was written as the app was built rather than derived from the package afterwards. It lives in three documents, and they are authoritative:

| Document | Covers |
|---|---|
| [`../../03-design/control-tower-native-experience-architecture.md`](../../03-design/control-tower-native-experience-architecture.md) | Information architecture, surfaces, and how they relate |
| [`../../03-design/control-tower-interaction-spec.md`](../../03-design/control-tower-interaction-spec.md) | Interaction patterns, states, and transitions |
| [`../../03-design/control-tower-visual-system.md`](../../03-design/control-tower-visual-system.md) | The visual system — the **Quiet Instrument** direction, tokens, and badge marks |

Read alongside them: [`../04-experience-design/60-ui-design.md`](../04-experience-design/60-ui-design.md) for the design tokens as actually implemented in SwiftUI, [`../04-experience-design/70-copy-voice.md`](../04-experience-design/70-copy-voice.md) for shipped copy strings and the banned-language list, and [`../05-design-challenge/00-brief.md`](../05-design-challenge/00-brief.md) for the eight critical views and the criteria by which a change to any of them is judged.

## What this route does not give you

Recorded honestly, because choosing this route has a real cost and the alternative would have surfaced these as explicit empty sections:

- **No accessibility specification exists.** No contrast audit, no light/dark Dynamic Type proof, no keyboard pass, no pinned tab order — for any surface. Finding **L1** in [`../../04-validation/audit-2026-08-02-findings.md`](../../04-validation/audit-2026-08-02-findings.md).
- **No consolidated component catalogue** with variants, states and usage guidance in one place. The information exists across the triad and `60-ui-design.md`, but a reader who wants a single component index does not have one.
- **Two divergent status vocabularies** remain undocumented as a single system — the tray's 12 badges and Settings' separate 5-state set. Finding **M2**.

If any of these becomes painful, the right response is to fix the underlying gap — run the accessibility pass, collapse the vocabularies — not to write a specification that describes the gap in more detail.

## If a Phase 6 artifact is ever needed

Should this product later need a conventional design-spec deliverable — an incoming design team, an accessibility audit, a component library extraction — the template at `/Volumes/Dev/Sites/CSE/product-creation-copilot/templates/06-prototype/10-design-spec.md` is still there, and the sources listed above are complete enough to fill it. The recommended shape is a **thin index** that answers each template section by pointing at the authoritative file, rather than restating content that already has an owner. That preserves one source of truth per fact, which is the property this repository lost once already.
