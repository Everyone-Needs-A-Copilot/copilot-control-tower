# DEC-4 — Delete or keep the stale clones (`conversations-copilot`, `shared-docs`)

> tc task: **TASK-118** (R-9, `phases/phase-3-soul-remediation.md`) · Claim:
> `knowledge-registry-completeness` (`claims.yaml`) · Status: prepared,
> **not ruled**. **Nothing has been deleted.** This memo only locates and
> describes what exists; only the owner rules on removal.

## 1. The decision, in one sentence

Of the two named stale-clone candidates, `conversations-copilot` does not
exist on this machine (already archived/renamed) and is a non-issue; a real
stale clone of the old `shared-docs` repo *does* exist, as a registered git
worktree at `/Users/pabs/.claude-worktrees/shared-docs/frosty-perlman`,
~6 months behind `main` — decide whether to remove it.

## 2. Context, in plain language

Knowledge Copilot used to be called `shared-docs`; it was renamed
2026-06-29 (ECOSYSTEM.md's own banner: *"Already have the old `shared-docs`
on your machine? Migrate with the guide..."*). Similarly, `conversations-copilot`
was renamed to `convoco`. Both renames leave a real risk: an old, un-updated
full clone sitting on disk under the old name, silently drifting out of
sync with the real repo while still looking legitimate to anyone who finds
it. R-9 flagged both names as deletion candidates. This memo actually went
and looked for them on disk, rather than assuming the names in the task
description still point at something real.

## 3. The evidence (located on disk, quoted with paths and timestamps)

**`conversations-copilot` — nothing to delete; already fully migrated.**
No directory by this name exists anywhere under `/Users/pabs/Sites/COPILOT`
(verified: `find`/`mdfind` across the whole visible tree). `ECOSYSTEM.md`'s
own "Out of scope / not tracked here" section lists it correctly:
*"**Archived (superseded)** → `_archive/`: ... `conversations-copilot`
(→ convoco)."* The actual archived content lives at
`knowledge-copilot/_archive/2026-06-conversations-copilot-renamed-convoco/`
— 7 files, 104K total, all with an mtime of **2026-06-28 14:32**. This is
exactly what a clean, completed migration looks like. There is no stale
duplicate anywhere to act on.

**`shared-docs` — two artifacts found; only one is a real stale clone.**

1. `/Users/pabs/Sites/COPILOT/shared-docs` — this is a **symlink**
   (`lrwxr-xr-x`, `readlink` → `knowledge-copilot`), not a duplicate
   directory. It resolves correctly to the current repo. It is not stale
   content; at most it's a convenience alias whose continued existence is a
   much lower-stakes, cosmetic call.

2. `/Users/pabs/.claude-worktrees/shared-docs/frosty-perlman` — this **is**
   a real stale clone. Confirmed via `git -C
   /Users/pabs/Sites/COPILOT/knowledge-copilot worktree list`, which shows
   it as an **officially registered git worktree** of the knowledge-copilot
   repo:
   ```
   /Users/pabs/Sites/COPILOT/knowledge-copilot               8d347a40 [main]
   /Users/pabs/.claude-worktrees/shared-docs/frosty-perlman  5c8b0d52 [frosty-perlman]
   ```
   Its remote is `https://github.com/Everyone-Needs-A-Copilot/knowledge-copilot.git`
   (confirmed via `git remote -v` inside it — same repo, pre-dating the
   Knowledge Copilot rename, still checked out under the old directory
   name). Its last commit is **2026-01-15 14:34:17 -0400**
   (`5c8b0d527ab997d802fba315d279d332b5759e18`, "feat(shared-docs): register
   29 technical skills and update agents") against today's `main` HEAD of
   **2026-07-13** (`8d347a40`) — **roughly 6 months stale**. `git status`
   inside it reports a clean working tree (no uncommitted work would be
   lost by removing it). Size on disk: **6.3M**.

**Registry-completeness context (the broader R-9 claim, for reference):**
`claims.yaml` (`knowledge-registry-completeness`, last checked 2026-07-12)
records: *"17/17 listed paths resolve, but copilot-control-tower is
entirely absent from ECOSYSTEM.md and knowledge-copilot never lists its own
local path; 12 top-level dirs unmentioned."* Verified directly against
`ECOSYSTEM.md` today: neither `knowledge-copilot` nor `copilot-control-tower`
appears as a Local-path row anywhere in the file. This session could not
regenerate the `knowledge_soul` collector's fresh registry numbers — it
errors in this sandbox (`"not a directory / not found," path:
/Volumes/Dev/Sites/COPILOT/knowledge-copilot`, because `/Volumes/Dev` isn't
mounted here and this session has no permission to create it). The
registry-completeness fix itself (adding the missing Local-path rows) is
the **non-owner-gated** part of R-9 and is not this memo's subject; this
memo is scoped to the deletion decision only, per the task.

**Caveat:** this audit only covers what's reachable from this machine and
this user account. It cannot speak to whether other developer machines
still carry an old-style `shared-docs` full clone under the old name — the
ECOSYSTEM.md migration banner implies that risk was anticipated for exactly
that reason.

## 4. Options and consequences

**Option A — Remove the stale worktree.** `git worktree remove` the
`frosty-perlman` worktree (the git-aware way — a raw `rm -rf` would leave
orphaned worktree metadata in `knowledge-copilot/.git/worktrees/` and could
cause confusing errors on future `git worktree` commands against the main
repo). *Consequence:* frees 6.3M and removes a 6-month-stale, easily
mistaken-for-current copy of Knowledge Copilot content from disk. The
working tree is clean, so nothing uncommitted is lost. Low risk.

**Option B — Keep it as-is.** *Consequence:* the stale clone remains
available (e.g., if the `frosty-perlman` branch/workspace was intentionally
set up for something not yet finished), but the registry-completeness
finding ("stale clone risk") stays open and someone could stumble into it
expecting current content.

**Option C — Archive instead of delete.** Move it somewhere clearly marked
non-canonical (e.g. rename the worktree directory or note it in
`ECOSYSTEM.md`'s "Out of scope" section) rather than removing it outright.
*Consequence:* preserves whatever branch history/content it holds in case
it's needed, at the cost of not actually resolving the "why does this
exist" question.

**Do nothing** (equivalent to Option B here, since there is nothing to
delete for `conversations-copilot` and the `shared-docs` symlink is already
correct): the only open item is the `frosty-perlman` worktree, and leaving
it means the stale-clone risk this decision exists to close stays open.

## 5. Recommendation (advice, not a ruling)

This is advice, not a ruling: Option A for the `frosty-perlman` worktree —
it is confirmed stale (6 months), confirmed clean (no uncommitted work),
and confirmed low-cost to remove via the proper `git worktree remove` path.
`conversations-copilot` needs no action (nothing found). The
`/Users/pabs/Sites/COPILOT/shared-docs` symlink is not a stale-clone problem
and can be left as a convenience alias unless the owner wants
`ECOSYSTEM.md`'s implied cleanup (removing legacy aliases entirely) applied
literally.

## 6. Exact one-line actions

- **Option A (remove worktree):** `git -C /Users/pabs/Sites/COPILOT/knowledge-copilot worktree remove /Users/pabs/.claude-worktrees/shared-docs/frosty-perlman`
- **Option B (keep):** `tc task update 118 --status blocked --metadata '{"decision":"keep"}'`
- **Option C (archive/flag instead):** `git -C /Users/pabs/Sites/COPILOT/knowledge-copilot worktree move /Users/pabs/.claude-worktrees/shared-docs/frosty-perlman /Users/pabs/.claude-worktrees/_archived-shared-docs-frosty-perlman`
- **Re-verify the worktree registration:** `git -C /Users/pabs/Sites/COPILOT/knowledge-copilot worktree list`
- **Re-attempt the fresh registry-completeness numbers (needs `/Volumes/Dev/Sites/COPILOT` mounted):** `cd tools/cse-bench && python3 cse_bench.py collect --only knowledge_soul`
