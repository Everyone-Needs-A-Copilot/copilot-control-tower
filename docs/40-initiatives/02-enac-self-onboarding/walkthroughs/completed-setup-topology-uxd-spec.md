# Completed Setup Topology — UX Specification

## Job

After onboarding, answer three questions without requiring the person to
remember setup terminology:

1. Is this Mac usable now?
2. Which Foundation, Organization, Department, and Personal parts exist for
   each Copilot component?
3. What can I finish later?

## Information architecture

The completed window has four sections in this order:

1. **Setup status** — separates machine usability from ecosystem completeness.
2. **Your copilots** — four component disclosures in the fixed Knowledge, CLI,
   Claude, Codex order.
3. **Your connections** — authentication and service connections only.
4. **Your projects** — the same five-classification aftercare route used in
   setup Step 7.

Every component disclosure contains four stable rows:

- Foundation
- Organization
- Department
- Personal

Rows never disappear. The helper-provided state is rendered as Ready, Needs
setup, Not joined, or Could not check.

## Primary incomplete state

When any Personal component is missing:

- headline: **Your copilots work, but Personal setup is incomplete**
- supporting line names the count, not a generic failure;
- primary action: **Finish Personal Setup**
- Personal is the tier label;
- Private appears only in supporting detail such as “Stored in a private GitHub
  repository only you can access.”

The action re-enters the existing onboarding transaction. It never creates a
repository merely because Settings opened.

## Projects

The summary uses `ProjectTriageRender.summary`. Every non-empty category is a
button. Selecting one opens the same Step 7 category, preserving guided launch,
diagnostics, verification, and continue-later behavior.

No legacy “need review” bucket appears.

## Failure and edge states

- Personal report unavailable: no completeness claim; show **Could not check
  Personal setup** and Retry.
- Department catalog available but none joined: each component says **Not
  joined** and the section may offer available departments separately.
- Department catalog unavailable: **Could not check**, never “Not joined.”
- No project folder: offer **Choose projects folder**.
- Empty folder: explain what folder was checked.
- Project report unavailable: scoped Retry; other sections remain usable.

## Accessibility

- Component disclosure labels include overall state.
- Tier rows combine tier, state, and detail for VoiceOver.
- Color is secondary to symbols and state text.
- Keyboard focus reaches every disclosure and category button.
