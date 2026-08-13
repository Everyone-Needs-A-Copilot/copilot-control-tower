# Progress evidence report visual specification

## Reader and job

The report serves the initiative owner answering three questions quickly: what is true now, what is blocked, and what must happen next. It is an evidence brief, not a health dashboard and not a celebration surface.

## Visual direction

Use the existing Control Tower **quiet instrument** system: hue-biased neutral canvas, restrained indigo, layered surfaces, compact monospaced evidence labels, and earned status color. The document should feel like a calm operating brief rather than generated Markdown.

## Hierarchy

1. Sticky product bar: report identity, maintenance state, and theme control.
2. Persistent status rail: disposition, task counts, and section navigation.
3. Editorial report surface: large title, compact provenance metadata, plain-language result, active gates, evidence matrix, and ordered path forward.
4. Claim boundary: visually last and intentionally sober.

## Tokens and components

- Typography: system sans for prose; system mono for evidence labels and metadata.
- Layout: 224-pixel status rail plus a readable report column capped near 920 pixels.
- Surfaces: 14–22 pixel radii, one-pixel borders, restrained shadows.
- Status roles: green only for accepted evidence, amber for active/partial, violet for pending, red for rejected/blocked.
- Tables: explicit header register, zebra rows, hover focus, horizontal overflow on small screens.
- Program snapshot: the existing four-row source table becomes a two-by-two card grid without changing its semantics.

## Responsive and access behavior

- Below 980 pixels, the status rail becomes an at-a-glance banner and horizontal section navigation.
- Below 680 pixels, snapshot cards stack and wide evidence tables scroll.
- Light and dark themes follow the operating system and can be overridden with a labeled control.
- Focus states, skip navigation, reduced-motion behavior, and print layout are first-class.
- The final report is self-contained and requests no external resource.

## Implementation handoff

`$uid` should preserve Markdown as the content source, use a committed Pandoc template and stylesheet, embed all resources into the final HTML, and validate rendered desktop/mobile/dark/print states. The design must not imply that partial or blocked evidence is complete.
