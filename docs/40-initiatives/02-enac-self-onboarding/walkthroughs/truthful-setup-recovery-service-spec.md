# Truthful Setup and Recovery — Service Design

Status: design walkthrough
Task: `tc` 183
Evidence: diagnosis task 182, work products 279–280
Product lens: Quiet Instrument

## Outcome

After installing Control Tower, a person who does not understand repositories,
manifests, or project scaffolding can answer:

1. Which copilots are ready on this Mac?
2. What is missing?
3. What can Control Tower safely set up?
4. Who will handle anything Control Tower cannot safely change?

“Everything is set up” is an evidence claim. It appears only after Control Tower
has verified every component the person is expected to have.

## Service promise

Control Tower observes, explains, and performs safe work. It does not ask the
person to interpret implementation details.

| Situation | What the person sees | What Control Tower does |
| --- | --- | --- |
| Component is verified | “Ready” plus named layer roles | Renders facts returned by `cc` |
| Expected component is absent | “Missing” plus one setup action | Asks `cc` to set up only missing components |
| Detail cannot be read | “Couldn’t verify” | Preserves the distinction between unknown and absent |
| One project copilot can be added safely | “Safe to add” | Applies that component without touching the existing one |
| Existing setup exactly matches a known legacy layout | “Recognized existing setup” | Offers a reviewed adoption path |
| Existing setup is custom or ambiguous | “Guided integration” or “Owner handoff ready” | Leaves the project unchanged and provides the competent actor a route forward |

## Frontstage journey

### 1. Check this Mac

Control Tower names Knowledge, CLI, Claude, and Codex before results arrive. It
shows a quiet checking state and never fills the interface with unexplained
circles.

### 2. Explain the inventory

Every copilot row has a text result. Layer roles use human labels:

- Core
- Organization
- Department, when applicable
- This Mac

An unavailable layer breakdown says “Layer details unavailable.” Unknown detail
never looks like a missing installation.

### 3. Complete missing personal setup

If personal Knowledge or CLI is absent, the primary action is “Set up 2 missing
spaces.” Supporting copy says the spaces are private and existing setup will be
preserved. Technical repository names are not shown in the primary journey.

### 4. Verify before advancing

After setup, Control Tower checks all four components again. The person advances
only when results are known. A failed item can be retried independently.

### 5. Explain the project inventory

Projects are grouped by meaningful next action:

- Ready
- Can finish safely
- Guided integration

The summary explains each count in a sentence before controls appear.

### 6. Apply only safe changes

Project readiness is evaluated per copilot. Existing Claude setup does not block
a safe Codex addition, and vice versa. The person sees what will be added and
what will remain untouched.

### 7. Route ownership correctly

Recognized, exact-match legacy setup can be adopted after review. Custom or
ambiguous content is left unchanged until the CLI prepares a guided integration
plan. An authorized author can open the project in Claude Code or Codex with the
CLI-generated prompt. A regular user receives an actionable owner handoff.

“Owner will review” without a prepared route, prompt, or verification step is not
a completion state.

### 8. State the result

The result separates:

- what was added;
- what was adopted;
- what was preserved;
- what remains with a project owner.

### 9. Continue in steady state

The menu-bar popover and Settings use the same inventory model. The aviators are
the only status-item identity. Healthy state is quiet; badges appear only when
there is a real next action.

## Backstage contract

The service requires the following `cc` contract:

1. `doctor` returns a canonical, closed `layer_role` separately from arbitrary
   manifest layer identifiers.
2. `doctor` returns expected, present, and health facts for Knowledge, CLI,
   Claude, and Codex.
3. Onboarding evaluates the complete four-component roster and fails closed when
   an expected component is absent.
4. Workspace preflight returns readiness, blocker, safe action, and responsible
   actor per component.
5. Adoption is available only when existing content matches a recognized legacy
   layout exactly.
6. Custom files are never overwritten.
7. The app renders `cc` facts; it does not invent a second scanner.

## Recovery rules

- Verification unavailable: “Couldn’t verify. Nothing changed.” Offer “Try
  again.”
- Older contract: show component status and “Layer details unavailable.”
- Personal setup failure: identify the failed component, confirm preserved
  setup, and retry only that component.
- Project conflict: name the copilot already present, the copilot that can be
  added, the content that will be preserved, and the responsible actor.
- Owner route: “A guided integration handoff is ready for the project owner.
  Nothing has been changed.”

The focused project variations are specified in
`project-integration-aftercare-service-spec.md`.

## Rejected alternatives

- Prefix-mapping arbitrary layer IDs inside the app.
- Treating a generic healthy result as complete when expected personal
  components are absent.
- Using one row-level `can_apply_now` Boolean for multiple copilots.
- Force-overwriting existing project files.
- Showing “Try again” when retry cannot change the result.
- Asking a nontechnical user to repair or migrate a project.
