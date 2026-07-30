# Project Integration Aftercare — UI Design Specification

Status: visual walkthrough
Task: `tc` 184
Companion: `08-project-integration-aftercare-uids-walkthrough.html`

## Direction

Continue **Quiet Instrument**. Project customization is presented as structured
capability, not as visual danger. The design becomes more specific only where the
person must understand responsibility and preservation.

## Hierarchy

1. Project integration result.
2. Plain-language explanation.
3. What is present, missing, and preserved.
4. One next action.
5. Technical evidence behind disclosure.

## State treatment

| State | Glyph | Color role | Primary language |
| --- | --- | --- | --- |
| Ready with project-specific setup | Check | restrained green | Ready |
| Can finish safely | Plus | blue | Safe finish available |
| Guided integration | Route/arrow | blue, not orange | Guided integration |
| Owner decision | Person | neutral | Waiting for project owner |
| Verification unavailable | Bang | red | Couldn’t verify |
| Stale plan | Clock | neutral | Inspect again |

Guided integration is not a warning. It is a supported route.

## Components

### Project capability summary

A compact inventory of:

- Claude entry point;
- Codex entry point;
- project agents;
- project skills;
- project protocols or rules.

### Preservation panel

Three rows:

- Will add
- Will preserve
- Will not change

This panel is reused in safe and guided paths.

### Use-case comparison card

Stable geometry across examples. Each card names:

- real representative project;
- detected pattern;
- correct route;
- final completion condition.

### Guided-plan card

Uses normal card treatment rather than warning treatment. The strongest visual
element is the destination action: Open in Codex or Open in Claude Code.

### Prompt preview

Monospaced only for the generated payload. User-facing summary remains in system
text. The full prompt is behind disclosure.

### Owner handoff

Neutral person glyph. The message emphasizes that nothing changed and the handoff
is ready. It does not show raw filenames or Git language to Bob.

## Responsive behavior

- Desktop uses the established stage rail plus detail register.
- Use-case maps may use two columns above 860 points.
- Below 700 points, the stage rail collapses and every comparison card stacks.
- Prompt actions wrap without horizontal overflow.

## Walkthrough requirements

- Sixteen numbered screens.
- Persistent table of contents and previous/next navigation.
- System/light/dark theme control.
- Reduced-motion support.
- No external resources or requests.
- Supplied aviators SVG retained wherever the Control Tower mark appears.
