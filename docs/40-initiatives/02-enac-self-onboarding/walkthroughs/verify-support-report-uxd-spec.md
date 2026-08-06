# Verify Support Report — UX Specification

## Product decision

The Verify holding state needs a durable, redacted support report. The current
identity-only block is not evidence and is not useful in a support conversation.
Raw `doctor --json` is also not an acceptable substitute because it contains a
host name and absolute paths.

This is an extension of the existing Holding disclosure, not a new diagnostics
screen or dashboard. The app renders the same CLI reports that caused the hold,
formats a closed set of non-private fields, saves that exact text privately, and
offers the same text for copying.

## Primary flow

1. Verify runs its existing `doctor → update (when offered) → doctor` sequence.
2. The model retains the first check, update receipt, and final check as one
   immutable verification attempt.
3. If the final check is not healthy, the Holding screen says only what the
   final CLI report proves and shows **Support report** collapsed by default.
4. Expanding it shows a short plain summary, the redaction promise, the saved
   report location using `~`, and a selectable monospaced preview.
5. **Copy support report** copies the complete report for a Claude Code, Codex,
   Discord, or human support conversation. **Show in Finder** reveals the exact
   saved file.

## Report contents

Allowed fields are closed and app-authored:

- Control Tower version and build
- packaged helper version when available as a release resource
- verification attempt timestamp
- initial and final `doctor` status plus schema version
- each non-pass check reduced to product, plain tier label, and severity
- update receipt result, schema version, changed/held/blocked counts
- explicit statement that host names, account names, organization names,
  project names, absolute paths, repository URLs, content, environment values,
  stdout/stderr, and secrets are omitted

The report never includes raw `detail`, `path`, `host`, auth identity, repository
name, layer id, item name, local/remote SHA, subprocess output, or arbitrary
error text.

## Required states

- **Saved:** preview, Copy, and Show in Finder are available.
- **Save unavailable:** the in-memory report remains previewable and copyable;
  the screen says it could not save the file and omits Show in Finder.
- **Copy success:** the button becomes **Copied** for two seconds and VoiceOver
  receives a polite confirmation.
- **Copy failure:** the label does not claim success; selectable report text
  remains available.
- **Repeat hold:** say **The latest check reached the same result.** Never claim
  “Nothing changed” without a completed-actions ledger.
- **Missing optional evidence:** omit the section or row; never print
  `unknown`, `nil`, or a dangling label.

## Accessibility

- Disclosure, preview, Copy, and Reveal follow the existing reading order.
- The disclosure label is **Support report**; its accessibility hint says it
  contains a redacted report suitable for sharing.
- The copy confirmation is announced without moving focus.
- Show in Finder is keyboard reachable and labeled **Show saved support report
  in Finder**.
- The report remains selectable when clipboard access fails.

## Boundaries

- No raw logging, telemetry, upload, or automatic support message.
- No app-side health judgment or repair decision.
- No new visual system. Existing DisclosureGroup, monospaced evidence block,
  secondary button, and Finder reveal patterns are reused.
- G-1 and G-2 are unchanged.

## Walkthrough

[25-verify-support-report-uxd-walkthrough.html](25-verify-support-report-uxd-walkthrough.html)
