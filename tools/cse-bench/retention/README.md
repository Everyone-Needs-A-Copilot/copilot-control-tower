# Transcript retention job

**TASK-84 (B-1), CSE Verification & Benchmark Program. URGENT / P0.**

## What this does

Mirrors Claude Code and Codex CLI transcripts into an append-only archive
on an hourly schedule, via a per-user `launchd` agent:

| Source | Destination |
|---|---|
| `~/.claude/projects/` | `~/.claude/transcript-archive/claude-projects/` |
| `~/.codex/sessions/` | `~/.claude/transcript-archive/codex-sessions/` |

The sync is `rsync -a` **without `--delete`**. A file updated at the
source overwrites its archived copy (same lineage, fine). A file removed
at the source is **never** removed from the archive by this job — there
is no flag or override for this; `--delete` is simply never passed to
`rsync` anywhere in this directory, including in `uninstall.sh`.

Each run appends one line to `~/.claude/transcript-archive/runs.log`
recording: ISO-8601 UTC timestamp, source file count, archive file count,
and archive byte size, for both sources.

## Why (F-6)

Claude Code's own retention policy is actively deleting transcripts —
observed corpus shrink from 113 to 108 sessions in roughly 24 hours during
Phase 1 of the CSE Verification & Benchmark Program. Deleted transcripts
are the **only irreversible data loss** identified across the whole
program: every other finding can be re-derived or re-measured; a deleted
transcript cannot. This job exists to stop that loss before Phase 2
analysis needs the corpus.

## Files

- `retain_transcripts.sh` — the archiver. POSIX-clean bash, `set -euo
  pipefail`, absolute paths, no dependency beyond `rsync`/`find`/`du`
  (all stock on macOS). Missing source directories are skipped with a log
  line, not a hard failure — e.g. a machine with no `~/.codex/sessions/`
  still successfully archives Claude Code transcripts.
- `com.copilot.cse.transcript-retention.plist` — LaunchAgent template.
  `StartInterval` 3600 (hourly), `RunAtLoad` true (also runs immediately
  on load/login). stdout/stderr both go to
  `~/.claude/transcript-archive/launchd.log`. Its `ProgramArguments`
  points at the repo copy of the script for readability; `install.sh`
  rewrites that path at install time (see below).
- `install.sh` — deploys a runtime copy of `retain_transcripts.sh`,
  writes the LaunchAgent plist into `~/Library/LaunchAgents/` (with the
  script path rewritten to the deployed copy), and bootstraps it into
  `gui/$UID` (falls back to `launchctl load` on older `launchctl` that
  doesn't support `bootstrap`).
- `uninstall.sh` — reverses `install.sh`: `bootout`/`unload`, removes the
  plist, removes the deployed runtime copy. **Never** touches the
  archive.

### Why `install.sh` deploys a copy instead of running the repo script in place

On this machine the repo lives on an external USB-attached volume
(`/Volumes/Dev`). macOS blocks launchd-spawned processes — `bash`, `cat`,
any system binary — from even *reading* files on that volume: a TCC
("Files and Folders") privacy protection for external volumes with no
scriptable grant path (it requires an interactive System Settings prompt,
and a headless launchd job has no UI to prompt with). This is independent
of file permissions or ownership — `chmod`/`chown` do not fix it, and it
was confirmed directly: `launchctl bootstrap` running `/bin/cat` on a
file on the repo volume fails with `Operation not permitted`, while the
identical file executed interactively (outside launchd) works fine.

`install.sh` works around this by copying `retain_transcripts.sh` to
`~/Library/Application Support/com.copilot.cse.transcript-retention/`
(on the boot volume, which launchd can read) and pointing the installed
plist's `ProgramArguments` at that copy instead of the repo path. The
repo copy stays the single source of truth for the script's logic —
**re-run `install.sh` after editing `retain_transcripts.sh`** to redeploy
the change; there is no symlink or live link between the two, since a
symlink resolving back onto the blocked volume would fail the same way.

If your repo lives on the boot volume (not an external drive), this
indirection is harmless — it just runs the same script from a second,
stable copy.

## Install

```bash
tools/cse-bench/retention/install.sh
```

## Verify

```bash
# Confirm launchd has the job loaded:
launchctl print gui/$UID/com.copilot.cse.transcript-retention | head

# Force an immediate run without waiting for the hourly interval:
launchctl kickstart -k gui/$UID/com.copilot.cse.transcript-retention

# Check the run log:
tail ~/.claude/transcript-archive/runs.log

# Check archive population:
find ~/.claude/transcript-archive/claude-projects -type f | wc -l
find ~/.claude/transcript-archive/codex-sessions -type f | wc -l
du -sh ~/.claude/transcript-archive/claude-projects
du -sh ~/.claude/transcript-archive/codex-sessions

# launchd's own stdout/stderr capture:
tail ~/.claude/transcript-archive/launchd.log
```

## Uninstall

```bash
tools/cse-bench/retention/uninstall.sh
```

This unregisters the LaunchAgent and removes the plist from
`~/Library/LaunchAgents/`. It does **not** delete
`~/.claude/transcript-archive/` — that archive is retained data, and
removing it defeats the entire purpose of this job. Delete it by hand if
you're certain you want to.
