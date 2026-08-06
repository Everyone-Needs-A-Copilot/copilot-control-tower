# User-controlled project handoff — architecture brief

## Decision

Keep `cc reconcile guide-prepare` as the sole author of project scope, the work
order, and the copy prompt. Swift decodes those values, opens Terminal at the
returned root, renders the prompt, and invokes `guide-finalize` only after the
person explicitly requests a check.

The native app must not resolve an assistant executable, launch an assistant,
pass prompt arguments, run `guide-start`, poll `guide-status`, or automatically
run `guide-finalize` when an external process exits.

## Boundaries

- Python owns selection, exclusions, file creation, prompt wording, package
  integrity, project checks, and completion.
- Swift owns presentation, pasteboard copy, opening the returned root in
  Terminal, opening the instruction file, and the explicit final-check action.
- Terminal owns only a normal shell in the approved root.
- Claude Code or Codex is entirely user-started and user-controlled.

## Contract changes

- The guide report gains one required `start_prompt` string authored by Python.
- `INSTRUCTIONS.md` uses the exact helper path in every verification command;
  it no longer depends on an environment variable exported by an app-launched
  shell.
- The existing guide lifecycle verbs remain available for compatibility, but
  the native handoff path calls only `guide-prepare` and `guide-finalize`.

## Failure modes

- Missing root or instruction file: no Terminal success claim; retain a fresh
  preparation action.
- Terminal open failure: keep the prompt and file available; never reinterpret
  it as an assistant failure.
- Tampered package: Python rejects final verification.
- App closure during the conversation: no monitored state is lost because no
  monitored state exists.
- User returns too early: the final check honestly reports remaining work.

## Rejected alternatives

- Keep the existing launcher but remove the spinner: still leaves the app in
  control of the assistant process.
- Generate the prompt in Swift: duplicates Python-owned package semantics and
  weakens the stable CLI boundary.
- Detect which assistant is installed before preparing: couples file creation
  to a choice the user can make later in Terminal.
- Add IPC from the assistant back to the app: creates a second orchestration
  channel and expands audit surface without improving verification.

## Verification plan

- Python schema and unit tests prove `start_prompt`, explicit helper commands,
  immutable package files, path safety, and fresh verification.
- Native contract tests prove Terminal receives only a quoted `cd` command and
  contains no assistant executable, work-order contents, lifecycle helper verb,
  or finalizer.
- Source checks reject polling and assistant-launch copy on the fleet path.
- Visual scenarios cover preparation, ready handoff, Terminal recovery,
  remaining work, and verified completion.
- Packaged-artifact tests run against the signed app and bundled helper.
