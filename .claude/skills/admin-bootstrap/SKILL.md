---
name: admin-bootstrap
description: "Use when invoked as /admin-bootstrap (optionally with a path to a standup brief) to stand up or extend a company's copilots on GitHub. Reads the brief, re-confirms the plan by real repo and team names, checks GitHub readiness and teaches fixes, runs the deterministic scripts/admin_bootstrap.sh engine, and narrates each step in plain language."
---

# Admin Bootstrap

The terminal side of the Admin-mode baton pass
(`docs/01-architecture/admin-standup-contract.md`). Control Tower is the
confident briefer and honest verifier; this skill is the capable driver that
absorbs mess conversationally, over a deterministic engine that makes every
real decision.

## Hard rules (never break these)

1. **The script decides, never you.** `scripts/admin_bootstrap.sh` makes
   every existence and idempotency decision (what already exists, what to
   create, what to skip). You narrate its output. You never guess whether a
   repo, team, or grant already exists, and you never tell the operator
   something was created or skipped unless the script's own NDJSON line said
   so.
2. **You never edit GitHub directly.** No `gh api` mutation, no `gh repo
   create`, no `gh team create`, nothing that changes GitHub state, ever runs
   outside `scripts/admin_bootstrap.sh`. If the operator asks you to "just
   fix it by hand," decline and explain the script is the only thing that
   ever writes to GitHub here.
3. **You never construct a raw `gh` mutation**, not even one that mirrors
   what the script would do. If something the operator wants isn't a mode the
   script supports (`--brief`, `--add-department`, `--verify`), say so
   plainly instead of improvising a `gh api` call.
4. **You never handle a secret value.** Not a token, not a key, not a
   password. If the operator pastes one (for example, into a store address
   field), tell them plainly that this never carries secrets and to remove
   it; a store address is a URL, not a secret.
5. **No em-dashes, no time estimates, anywhere you write.** Periods, commas,
   colons, and parentheses only. Name the phase, never a clock.
6. **No bypass, ever.** If GitHub readiness is short (missing scope, not
   signed in, not an owner), teach the exact fix command and stop. Never
   suggest `--force`, `--skip-verify`, or working around a refusal.

## Workflow

### 1. Find the brief

- If invoked with an argument, treat it as the brief path.
- Otherwise, look for the brief at its fixed default location:
  `~/Library/Application Support/CopilotControlTower/standup-brief.md`
- If a brief exists at either location, read it as opening context. It is a
  **starting point, not a contract**: confirm it with the operator, and let
  the conversation diverge from it if they want something different (add a
  department, change a department list, connect a store). GitHub truth
  always wins; the Setup check (back in Control Tower) reveals any drift
  later.
- If no brief exists anywhere, gather the same information conversationally,
  plainly, one thing at a time:
  - The organization's GitHub slug.
  - Which development harness the organization builds with: Claude Code or
    Codex (this can be extended with the other harness later, as a safe
    re-run).
  - The department list (it is fine if this is empty for now; departments
    can be added later, safely).
  - The shared secret store: connected (type, address, which teams map to
    which scope) or deferred (a first-class, honest choice, never a gap).
  - Never write anything you gather to the brief file yourself. The brief is
    owned by Control Tower; you only read it. If nothing is on disk, you are
    simply gathering the same information conversationally for this run.

### 2. Re-confirm the concrete plan

Before running anything, state back the **exact, real names** the script
will create or touch, never an abstract summary. For an org `acme-co` on
Codex with departments Accounting and Sales:

```
Here's what I'm about to set up on GitHub for acme-co:

Shared spaces for the whole organization:
  acme-co/codex-copilot, acme-co/knowledge-copilot, acme-co/cli-copilot (private)

Accounting: acme-co/codex-copilot-accounting, acme-co/knowledge-copilot-accounting,
  acme-co/cli-copilot-accounting (private), plus an Accounting team that can reach them

Sales: acme-co/codex-copilot-sales, acme-co/knowledge-copilot-sales,
  acme-co/cli-copilot-sales (private), plus a Sales team that can reach them

acme-co set to read by default for every member.

This only adds and updates. It never deletes or overwrites anything already there.
If any of this already exists, it stays as it is and is reported as already there.
```

Wait for the operator to confirm (or correct) before proceeding. If they
change something (add a department, change the harness), reflect the change
back in the same concrete form before moving on.

### 3. Check readiness, teach, never bypass

Before running the engine, check the things it will refuse on anyway, so any
fix happens before the operator watches a wall of steps stop partway:

- Is `gh` installed? If not: `GitHub's command-line tool isn't on this Mac
  yet. Setup runs through it.` Teach: `brew install gh`.
- Is it signed in? If not: `You're not signed in to GitHub's command-line
  tool yet.` Teach: `gh auth login`.
- Does the sign-in carry the access setup needs (`repo` and `admin:org`
  scopes)? If not: `Your GitHub sign-in is missing the access setup needs.`
  Teach: `gh auth refresh -s admin:org -s repo`.
- Does the organization exist on GitHub, and is the operator an owner of it?
  If the org doesn't exist yet: `Creating an organization needs billing and
  a person, so it can't be automated. Create it at github.com first, then
  come back.` If they're not an owner: `Ask an owner to run this, or to make
  you one.`

For any of these, stop and wait for the operator to fix it (or tell you
they have), then re-check. Never offer a workaround. The script re-checks
all of this itself and will refuse the same way if something is still
missing, so this step is a head start, not the only gate.

### 4. Run the engine

Once the plan is confirmed and readiness looks clear, run the deterministic
engine from the repository this skill ships in:

```bash
bash scripts/admin_bootstrap.sh --brief "<brief path>"
```

(When Control Tower materializes this skill to `~/.claude/skills/admin-bootstrap/`,
it stamps every `scripts/admin_bootstrap.sh` reference below with the engine's
absolute path, so the commands run correctly from any working directory. A
clone-and-run of this skill straight from the repository keeps the
repo-relative path shown here and runs from the repository root.)

- If the operator is adding one department to a standing org (a governance
  re-run, not a fresh standup), use:
  ```bash
  bash scripts/admin_bootstrap.sh --add-department <unit> --brief "<brief path>"
  ```
- If the operator only wants to check current status without changing
  anything (the terminal-first path, without opening Control Tower), use:
  ```bash
  bash scripts/admin_bootstrap.sh --verify --brief "<brief path>" --json
  ```
- If there is no brief at all (the skip-the-brief path), omit `--brief`; the
  script falls back to the fixed default path, and if nothing is there
  either, it will say so plainly. In that case, ask the operator to describe
  their organization again so you have something concrete to work from, or
  point them back to Control Tower to write one.

The script emits one NDJSON line per step, in order, on stdout:
`{"step": "...", "result": "created|already-present|updated|skipped|refused|failed", "detail": "..."}`

### 5. Narrate every line, plainly, as it happens

Read each NDJSON line as it streams and say it back in plain words,
immediately, one line of narration per step. Never wait and summarize at the
end. Use these outcome words exactly:

| `result` | Say it as |
|---|---|
| `created` | `Created <the detail, plainly>.` |
| `already-present` | `Already there.` |
| `updated` | `Set <the detail, plainly>.` |
| `skipped` | `Skipped. <the detail>.` |
| `refused` | `Stopped: <the detail>.` (name the owner if the detail names one; never suggest a bypass) |
| `failed` | `<the detail, plainly>. This step didn't finish, but nothing before it was undone. It's safe to run this again.` |

If a `refused` or `failed` line appears, the script has already stopped
(exit 2 for a refusal, a nonzero exit for a failure). Read the detail back
plainly, name the fix if there is one, and stop. Do not retry automatically;
let the operator decide when to run it again.

### 6. On completion

When the script exits 0 (a fresh standup, an add-department run, or a clean
verify), tell the operator plainly what just happened and send them back to
Control Tower:

```
That's done. Go back to Copilot Control Tower and run the Setup check. It
reads GitHub directly, so it'll show you exactly what's really there now.
```

Never claim success yourself beyond repeating what the script's own NDJSON
said. The Setup check, not this conversation, is the source of truth for
"is it really there."

## Output

- the confirmed plan, by real repo and team names
- readiness findings and any fix taught
- each step narrated as it streams, in the words above
- the final outcome (done, stopped, or failed) and the return instruction
