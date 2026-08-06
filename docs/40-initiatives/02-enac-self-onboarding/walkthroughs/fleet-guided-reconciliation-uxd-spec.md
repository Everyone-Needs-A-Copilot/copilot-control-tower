# Fleet-guided reconciliation — UX specification

## Primary flow

1. The existing project batch states how many projects can continue and how
   many remain protected.
2. The user chooses **Finish with Codex** or **Finish with Claude Code**.
3. A short preparing state says that Control Tower is writing one set of
   instructions; it makes no change claim.
4. Terminal opens at the approved Sites root with the complete instruction file
   already passed to the assistant.
5. Control Tower shows one fleet progress surface: verified count, remaining
   count, and the latest Python-authored detail. It offers **Bring Terminal
   forward**, **Open instruction file**, and **Copy instructions**.
6. When the assistant exits, Control Tower runs a fresh whole-batch check.
7. Ready advances. Remaining work offers **Continue in Codex**, **Continue in
   Claude Code**, or **Leave these projects for later**.

## Alternate and recovery flows

- Chosen assistant unavailable: retain the package and offer the other route.
- Automation permission denied: show the exact System Settings location and a
  Try Again action.
- Terminal unavailable: offer Open instruction file and Copy instructions.
- App reopened during a run: read Python status and offer Continue in the same
  run package.
- No selected projects: disable both launch actions and retain the selection
  explanation.
- Projects still unresolved after final verification: group the count and the
  next actor; do not render rollback implementation details as failure reasons.
- Update available during final Verify: run the update, show the named phase,
  and call Doctor again.

## Product language

- Title before launch: **Finish your projects in one guided session**
- Intro: **Control Tower will write one set of instructions for this folder and
  open it in the assistant you choose. You can ask questions there while it
  works through every selected project.**
- Active title: **Your guided setup is open in Terminal**
- Active detail: **Python will count a project only after a fresh check passes.**
- Ready: **Every selected project passed a fresh check.**
- Remaining: **Some projects still need the same guided conversation.**
- Restoration detail is collapsed to: **The previous project setup was restored.**

## Accessibility

- Focus moves to the new state heading after preparation and finalization.
- Buttons use native controls and name the assistant explicitly.
- Progress is expressed as counts and text, never colour or animation alone.
- Status changes use one polite live announcement; no repeated per-project
  announcements.
- **Bring Terminal forward** remains keyboard reachable throughout the active
  and remaining states.

## Walkthrough

[23-fleet-guided-reconciliation-uxd-walkthrough.html](23-fleet-guided-reconciliation-uxd-walkthrough.html)

