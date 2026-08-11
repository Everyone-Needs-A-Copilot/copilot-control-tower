# Step 7 Project Triage and Aftercare — UI Design Specification

Status: owner-review visual walkthrough

Task: `tc` 195

Companion: `08-project-integration-aftercare-uids-walkthrough.html`

## Direction

Continue **Quiet Instrument**, now applied as a focused triage surface. The
interface should feel like a calm control desk: one count, one category, and one
next action at a time.

The design removes the continuous report-like register shown in the observed
build. Project capability remains positive; uncertainty is specific rather than
visually alarming.

## Hierarchy

1. Total projects and the plain-language result sentence.
2. Three selectable status cards with counts and next-action meaning.
3. One focused category register.
4. One selected project and its next action.
5. Technical evidence behind disclosure.

Counts are large enough to scan but never behave like decorative dashboard
metrics. Zero-count categories disappear from the primary row.

## Layout

- The existing setup rail remains unchanged.
- The content column is capped at 920 points for overview and list states.
- Category cards form a three-column row at wide desktop sizes.
- Selecting a card replaces the content beneath it; cards do not vertically
  expand.
- Category registers show at most six projects per page.
- Project detail uses a 60/40 split for action and evidence when space allows.
- The bottom setup action remains visible without requiring the person to scroll
  past project rows.

## Components

### Status selector

Each card contains:

- count;
- user-facing label;
- one-sentence meaning;
- selected indicator.

Ready uses restrained green only for its glyph. Needs guided setup uses the
standard blue action role. Couldn’t confirm uses a neutral question glyph and
normal text; red is reserved for a specific failed check or blocked action.

### Focused project row

Rows contain project name, one plain-language reason, compact capability counts,
and one explicit action. Raw technical reason identifiers are excluded.

### Next-step panel

Guided and diagnostic detail begin with a lightly tinted panel:

- what this project needs;
- what will happen when the primary action is used;
- what Control Tower will verify afterward.

### Preservation register

Detected, Required, Preserve, and Do not change use stable labeled rows. “Do not
change” is a safety boundary, not a red error paragraph.

### Execution tracker

Visible assistant work uses four states:

1. Opening Terminal.
2. Guided setup running.
3. Session ended.
4. Control Tower verifying.

The tracker shows a textual state, project name, chosen assistant, and
**Bring Terminal forward**. A compact terminal preview provides confidence
without becoming an embedded terminal.

### Evidence disclosure

Couldn’t-confirm detail groups evidence by Claude and Codex. Plain-language
reasons are visible; paths, contract IDs, and the verification command are
disclosed on request.

## Product language presentation

- Sentence case everywhere except the established setup-step eyebrow.
- Use “Needs guided setup” rather than “Guided integration.”
- Use “Couldn’t confirm” rather than “Couldn’t verify” in primary UI.
- Use “Nothing changed” directly beside failure and cancellation messages.
- Use “Continue setup” for the onboarding footer.
- Do not display explanatory taxonomy prose below the counts.

## Responsive behavior

- Above 980 points: three category cards and split project detail.
- From 700–979 points: cards remain three columns; detail becomes one column.
- Below 700 points: category cards become a horizontal snap list, the setup rail
  collapses, lists remain paginated, and bottom actions stack.
- No state introduces horizontal page scrolling.

## State styling

| State | Treatment |
| --- | --- |
| Ready | restrained green check, normal surface |
| Needs guided setup | selected blue border and action |
| Couldn’t confirm | neutral question glyph; specific failed evidence may use red text |
| Running | blue progress ring plus text; animation removed under reduced motion |
| Verifying | indeterminate native-style progress and live status |
| Owner decision | neutral person glyph and handoff action |
| Stale plan | neutral clock glyph and Inspect again |
| Launch failure | bordered inline recovery panel; no full-screen alarm |
| Empty folder | quiet empty state with folder name and two actions |

## Implementation notes for `$uid`

- Preserve the setup rail, native window chrome, system type, spacing rhythm,
  button geometry, and semantic color roles already used by the app.
- Keep category selection state separate from CLI classification state.
- Use virtualized or paginated presentation; do not render all categories as one
  continuous document.
- Keep the footer outside the category scroll region.
- Do not infer progress or completion from assistant text. Only process lifecycle
  and CLI verification may advance the execution tracker.
- Render Diagnose actions only when the helper supplies its structured
  read-only diagnostic payload. Older helpers retain exact evidence, Copy
  diagnostic report, and Check again without displaying a dead control.

## Walkthrough coverage

The companion walkthrough contains sixteen numbered screens covering loading,
overview, guided setup, visible execution, launch recovery, verification,
couldn’t-confirm evidence, Ready reassurance, owner decision, stale plan, empty
folder, and return-to-setup completion.
