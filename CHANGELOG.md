# Changelog

All notable changes to Copilot Control Tower are recorded here.

## [0.2.2] - 2026-07-31

### Fixed

- **Run in Codex** and **Run in Claude Code** now open a visible Terminal
  session in the selected project and start the installed assistant with the
  complete CLI-generated prompt.
- The app resolves each assistant to its absolute executable before opening
  Terminal, avoiding Finder/Terminal `PATH` differences.
- Terminal receives the command before it is brought forward, preventing a
  separate empty startup window from hiding the guided session.
- A missing project folder or denied Terminal automation permission now shows
  a specific recovery message while keeping the copied prompt available.

### Security

- The signed User app now carries the Apple Events entitlement and purpose
  string required by macOS to request Terminal automation permission. macOS
  still requires the person's approval; Control Tower gains no Accessibility
  or UI-scripting permission.
- Guided prompts remain data in owner-only temporary files, while executable,
  project, and prompt-file paths are shell-quoted. Independent `cc` project
  verification remains the only way to mark a project Ready.

### QA

- The release gate now rejects a signed app that lacks either the Terminal
  automation entitlement or its user-facing purpose string.
- In-binary regression coverage verifies absolute assistant invocation,
  project-directory handling, prompt-file safety, Terminal ordering, and
  actionable Apple Events denial handling.

### Rollback

- Reinstall the signed `0.2.1` DMG to return to the previous release. Tags are
  immutable; a defective `0.2.2` must be superseded, never moved.

## [0.2.1] - 2026-07-30

### Added

- A returning-person ecosystem view for Knowledge, CLI, Claude, and Codex,
  with expandable Foundation, Organization, Department, and Personal status.
- A direct “Finish Personal Setup” route when any required Personal space is
  missing or incomplete.
- Project aftercare category cards in the completed app that reopen the same
  focused Step 7 experience used during setup.

### Changed

- “Personal” is now the user-facing tier name throughout Control Tower.
  “Private” is shown only as the GitHub repository visibility that protects a
  Personal space.
- Project aftercare emphasizes that people can finish one or two projects and
  return later; setup no longer implies every project must be completed in one
  session.
- The embedded helper is now `cc 1.7.14`, and
  `controltower.compat.json` requires that exact minimum contract.

### Fixed

- Aggregate onboarding now provisions all four Personal spaces—Knowledge,
  CLI, Claude, and Codex—even when Claude and Codex are the selected assistant
  runtimes.
- The completed app no longer claims the ecosystem is ready when required
  Personal spaces are missing.
- The completed Projects section no longer collapses actionable projects into
  an unexplained “needs review” total.

### Rollback

- Reinstall the signed `0.2.0` DMG to return to the previous known-good build.
  Foundation and app tags are immutable; a defective `0.2.1` must be
  superseded, never moved.

## [0.2.0] - 2026-07-30

### Added

- Focused Step 7 project triage with expandable, searchable, paginated
  categories instead of one continuous project list.
- Clear Ready, guided setup, owner decision, and couldn't-confirm detail views
  with actionable next steps and explicit “finish later” guidance.
- Visible Terminal sessions for Codex and Claude Code guided setup, followed by
  independent helper verification.
- Helper-authored, read-only diagnostic routes for projects whose integration
  evidence cannot yet be confirmed.
- Persistent project aftercare access from the Control Tower menu so project
  setup does not have to be completed during initial onboarding.

### Changed

- The embedded helper is now `cc 1.7.13`, produced from signed foundation tag
  `v5.13.15` and pinned by SHA-256.
- `controltower.compat.json` now declares app `0.2.0` and raises the minimum
  supported helper version from `1.7.11` to `1.7.13`.
- The JSON `schema_version` remains `1.0`; the helper diagnostic field is
  additive and optional for backward-safe decoding.

### Fixed

- Assistant launch controls now open an observable Terminal workflow instead
  of appearing to do nothing.
- Couldn't-confirm projects now show the exact evidence received and the
  smallest safe diagnostic action instead of leaving the user without a route.

### Security

- Diagnostic prompts are explicitly read-only, temporary prompt files use
  owner-only permissions, and only authoritative `cc workspace verify` results
  can mark a project Ready.

### Rollback

- Reinstall the signed `0.1.9` DMG to return to the previous known-good build.
  Foundation and app tags are immutable; a defective `0.2.0` must be
  superseded, never moved.
