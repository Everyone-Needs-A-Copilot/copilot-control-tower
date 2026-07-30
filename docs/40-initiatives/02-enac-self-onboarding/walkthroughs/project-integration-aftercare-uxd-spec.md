# Step 7 Project Triage and Aftercare — UX Specification

Status: owner-review walkthrough

Task: `tc` 195

Companion: `07-project-integration-aftercare-uxd-walkthrough.html`

Evidence: owner screenshot review and read-only `cc workspace verify` results from
`admin-server`, `convoco`, and `copilot-control-tower`

## Primary task

Understand the project inventory without reading a 53-row report, focus on the
projects that need attention, complete one supported route, and continue setup
without losing unfinished project work.

Step 7 is a triage hub. It does not require the person to resolve every project
during onboarding.

## Information architecture

The default view contains one result sentence and one selectable card per
non-zero category:

1. **Ready** — already set up; no action needed.
2. **Needs guided setup** — project-owned capability must be preserved while an
   assistant completes the integration.
3. **Couldn’t confirm** — capability was found, but the CLI could not prove that
   it meets the current contract.

`Can finish safely` and `Needs an owner decision` appear only when their count is
non-zero. The five-state CLI vocabulary remains available behind “How this is
classified”; zero-value states and taxonomy prose do not occupy the overview.

For the observed inventory, the primary copy is:

> **53 projects found**
>
> 17 are ready. 17 need guided setup. Control Tower couldn’t confirm 19.

Selecting a category replaces the register below it. Categories do not expand
into one combined 53-row page. Lists are searchable, paginated, and retain the
selected row when the person returns from detail.

## Primary flow

1. Control Tower checks only the selected project folders and reports progress.
2. The overview presents the three observed, non-zero categories.
3. The person opens **Needs guided setup**.
4. A focused list explains why each project needs help.
5. Project detail leads with what happens next, followed by Detected, Required,
   Preserve, Do not change, and technical evidence.
6. The person chooses an installed assistant.
7. Control Tower opens a visible Terminal session in the project directory and
   passes through the CLI-generated prompt.
8. Control Tower reports that the session is running and provides
   **Bring Terminal forward**.
9. When the session ends, Control Tower invokes authoritative CLI verification.
10. The project becomes Ready only when that verification passes.
11. The overview updates while preserving all remaining work for later.

## Couldn’t-confirm recovery

“Verify again” is not the default action when nothing changed.

The project detail must render the CLI’s component-level evidence:

- what was found;
- what could not be proven;
- which component is affected;
- whether the evidence was missing, mismatched, unreadable, or outside the
  trusted project boundary;
- that nothing was changed.

For `convoco`, the walkthrough uses the current read-only evidence:

- Claude: `CLAUDE.md` does not expose the recognized Claude entry;
- Codex: two framework files mismatch the expected variant;
- Codex: `.codex-copilot.json` does not name the project-local plugin;
- Codex: the skill bridge points outside the project plugin.

The non-technical summary is shown first. Raw paths and requirement identifiers
remain behind **Show technical evidence**.

The primary recovery is **Diagnose in Codex** or **Diagnose in Claude Code**.
This starts a visible, read-only diagnostic session using a CLI-generated
diagnostic payload. It may inspect and explain; it may not change project files.
After diagnosis, the CLI may return a guided plan, an owner decision, or a
corrected Ready verdict.

**Check again** is secondary and labelled “Use after the project setup changes.”

## Ready route

Ready is intentionally quiet:

> **17 projects are ready**
>
> Claude and Codex passed authoritative verification. Nothing else is needed.

The optional list shows project name, capability summary, and verification
recency. Detail states the Claude and Codex results and avoids internal phrases
such as “Only the helper can mark this project Ready.”

## Alternate and recovery flows

- **Assistant unavailable:** name the missing assistant, state that nothing
  changed, and offer the other installed assistant, Copy prompt, and Retry.
- **Session canceled:** retain the plan and offer Resume or Check project now.
- **One requirement remains:** show only the remaining requirement and return to
  the reviewed plan.
- **Owner decision:** state the exact decision, prepare a shareable handoff, and
  keep the project incomplete.
- **Project changed since inspection:** invalidate the old plan, explain why, and
  offer Inspect again.
- **No projects found:** state which folder was checked and offer Choose another
  folder or Continue setup.
- **Folder unavailable:** identify the folder and offer Reconnect folder without
  removing other results.
- **Safe finish becomes non-zero:** insert its card between Ready and Needs
  guided setup with the CLI-declared bounded action.

## Product language

| Internal classification | Primary language | Supporting language |
| --- | --- | --- |
| `ready` | Ready | No action needed |
| `safe-finish` | Can finish automatically | Review the exact additions first |
| `guided-integration` | Needs guided setup | A coding assistant can complete this while preserving project-owned capability |
| `owner-decision` | Needs the project owner | A named decision is required before work can continue |
| `could-not-verify` | Couldn’t confirm | Setup was found, but Control Tower cannot yet prove it is current |

Primary actions describe intent: **Review guided projects**, **Run guided setup**,
**Diagnose**, **Inspect again**, and **Continue setup**. “Review plan” may remain
as a secondary technical label. “Continue without projects” is removed.

## Accessibility

- Category selectors use a single-select tab pattern with count, label, and
  description in the accessible name.
- The selected category is not communicated by color alone.
- List results announce the displayed range and total.
- Opening detail moves focus to the project heading; Back returns focus to the
  originating project row.
- Disclosures use native button semantics and expose expanded state.
- Launch, running, verification, and result changes use polite live regions.
- Errors that require action receive focus; ongoing progress does not steal it.
- Terminal progress remains understandable without relying on animation.
- All controls meet a 44-by-44-point target where the native shell permits.

## Service and technical dependencies

1. The CLI generates a read-only diagnostic payload for detail-scoped
   `could-not-verify`; the app passes it through and does not compose it.
2. External launch needs an observable lifecycle: assistant selected, Terminal
   started, process running, process ended, and verification invoked.
3. Launch must open the selected project directory and pass the exact
   CLI-generated payload rather than only copying it.
4. The app needs stable component-level reason text and evidence categories from
   the CLI.
5. Category filtering and pagination must remain presentation only; all counts
   and classifications come from the CLI report.

## Walkthrough sequence

1. Checking the selected folder.
2. Focused 53-project overview.
3. Needs-guided-setup list.
4. Guided project detail.
5. Choose an assistant.
6. Visible Terminal session.
7. Assistant unavailable recovery.
8. Independent verification.
9. Guided result variants.
10. Couldn’t-confirm list.
11. Exact couldn’t-confirm evidence and diagnosis route.
12. Ready list and detail.
13. Owner-decision edge state.
14. Stale-plan edge state.
15. Empty-folder edge state.
16. Updated overview and Continue setup.
