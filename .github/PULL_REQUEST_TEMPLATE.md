## What does this change do?

<!-- One or two sentences. Link the issue this closes, if any. -->

## Invariant checklist

Every one of these must be checked (or explicitly not applicable, with a
one-line reason) before this PR can merge. See [`CLAUDE.md`](../CLAUDE.md)
for the full invariant text and [`SOUL.md`](../SOUL.md) §5 for the Feature
Filter this was run against.

- [ ] **Does not add resolution/sync/merge/signature-verify logic to the app**
      (invariant #1, parse-never-compute). All ecosystem-state decisions still
      come from a CLI `--json` verb the app only renders.
- [ ] **Does not weaken security posture** (invariant #4). No new
      `--skip-verify`/`--force` path; no security-sensitive config read from a
      user-editable domain; no new bypass or "unstick it" mode.
- [ ] **Respects never-destroy** (invariant #3). Nothing here can touch a
      dirty personal working tree; re-materialization only affects disposable
      mirrors.
- [ ] **Does not introduce cross-tier write capability or upward sync**
      (invariant #6). No personal-holding path gains write access to a
      shared/org/dept remote; no secret enters git or inheritance content by
      value (references only).
- [ ] **Single-process discipline held** (invariant #2). No new daemon, no
      in-app fallback loop, `KeepAlive` (if touched) stays
      `{SuccessfulExit:false}`, never `true`.
- [ ] **Routing checked** (invariant #5). Any new prompt/notification is
      routed to the actor who can actually act on it — not just whoever is
      closest to the menu bar.

## Testing

- [ ] Tests added or updated for this change
- [ ] Contract tests updated if this touches parsing of `--json` CLI output
- [ ] Manually verified locally (describe how, if not covered by automated
      tests)

## Documentation

- [ ] Docs updated in this PR (which file(s)?) — a behavior change without a
      doc update is incomplete
- [ ] N/A — no user-facing or contributor-facing behavior changed

## Screenshots / output (if applicable)

<!-- Tray states, wizard screens, Admin dashboard, or --json output before/after. -->
