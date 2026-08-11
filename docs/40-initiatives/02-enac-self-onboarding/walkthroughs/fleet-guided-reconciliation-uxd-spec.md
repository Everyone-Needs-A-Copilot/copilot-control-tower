# User-controlled project handoff — UX specification

## Primary flow

1. The batch states how many projects are included and how many were kept out
   of scope.
2. The user chooses **Prepare instructions and open Terminal**. No assistant
   choice is required yet.
3. A short preparing state says only that Python is writing the work order and
   copy prompt.
4. Terminal opens at the approved Sites root and stops at a normal shell prompt.
   Nothing else is typed, pasted, or started.
5. Control Tower shows four numbered instructions:
   1. In Terminal, type `codex` or `claude` and press Return.
   2. Choose **Copy prompt** in Control Tower.
   3. Paste the prompt into the assistant and send it.
   4. Talk to the assistant normally; ask questions or answer its questions
      until the work is finished.
6. The short Python-authored prompt is visible and copyable. It points the
   assistant at the complete work-order file; it does not inline that file.
7. When the user is ready, they choose **Check the projects**. Control Tower
   runs a fresh Python check only then.
8. Ready advances. Remaining work keeps **Copy prompt**, **Show Terminal**,
   **Open instruction file**, and **Check again** available.

## Alternate and recovery flows

- No selected projects: preparation is disabled and the selection explanation
  remains visible.
- Terminal unavailable or permission denied: retain the package, show the Sites
  path, and offer **Try opening Terminal again**, **Copy prompt**, and **Open
  instruction file**. Do not mention an assistant launch failure.
- Assistant unavailable or not signed in: the app makes no claim because it did
  not start or inspect the assistant. The instructions tell the person to ask
  the assistant for help or switch between Codex and Claude Code.
- App reopened later: a fresh assessment may create a new package; a prepared
  screen never claims that a previous conversation is still running.
- Final check finds remaining work: list Python's current reasons and explain
  that the same conversation can continue from the same file.
- Package unreadable or incompatible: say that the instructions could not be
  confirmed and require a fresh preparation. Never show a stale prompt.

## Required states

- Selecting
- Preparing the files
- Instructions ready / Terminal opened
- Terminal opening failed
- Running the explicit final check
- Remaining work after a fresh check
- Verified ready

There is deliberately no assistant-running state.

## Product language

- Selection title: **Prepare one set of project instructions**
- Selection intro: **Control Tower will write one work-order file for every
  selected project and open Terminal at your Sites folder. It will not start
  Claude Code or Codex.**
- Primary action: **Prepare instructions and open Terminal**
- Handoff title: **Your project instructions are ready**
- Handoff intro: **Terminal is open at your Sites folder. You choose which
  assistant to start and you control the conversation.**
- Prompt label: **Prompt to paste into Claude Code or Codex**
- Primary handoff action: **Copy prompt**
- Verification action: **Check the projects**
- Remaining: **The fresh check found projects that still need work. Continue
  the same conversation with the same prompt.**
- Ready: **Every selected project passed a fresh Python check.**

## Accessibility

- Focus moves to the handoff heading after preparation and to the result heading
  after final verification.
- The four steps are a semantic ordered list in reading order.
- The prompt has a descriptive label and can be copied without selecting text.
- Copy confirmation is a polite, one-time status announcement.
- Buttons are native controls with visible text; no action depends on colour.
- The preparing and final-check spinners have specific accessibility labels.
- No repeating announcement or animation implies assistant activity.

## Walkthrough

[23-fleet-guided-reconciliation-uxd-walkthrough.html](23-fleet-guided-reconciliation-uxd-walkthrough.html)

