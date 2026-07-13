# DEC-7 — C-3 hook rollout: ready to widen, or hold for one real session?

> tc task: **TASK-103** (C-3, `phases/` staged-rollout series) ·
> Doc: [`claude-copilot/docs/10-architecture/06-hook-deadlock-root-cause-2026-07.md`](../../../../../claude-copilot/docs/10-architecture/06-hook-deadlock-root-cause-2026-07.md) ·
> Status: prepared, **not ruled**. **No consumer repo has had the hook
> matcher widened.** A real defect in `claude-copilot`'s own hook wiring has
> been fixed; the rollout-readiness gate has not.

## 1. The decision, in one sentence

The path defect that made `claude-copilot`'s deadlock fix (`77f5cdb0`)
non-executable on this machine is now fixed and passes every scripted
verification available — rule whether that's sufficient to satisfy Rollout
Readiness condition 1 ("a full real working session, no unexpected denials"),
or whether it still requires the owner to actually run one.

## 2. Context, in plain language

`claude-copilot`'s "mechanical delegation enforcement" hooks had a real
deadlock bug (April 22 – July 12, 2026): a subagent sharing its parent's
`session_id` could get silently denied with no escape hatch. `77f5cdb0` fixed
the mechanism (subagent exemption via `agent_type`, `CC_HOOK_ENFORCE` kill
switch, fail-open hardening) and is proven via a 49-assertion replay suite
plus a scratch-project live smoke test. The same commit's own doc gates any
consumer-repo rollout (C-3) on three conditions, the first being: *this
repo's own live `.claude/settings.json` must run the widened matcher through
a real working session with no unexpected denials.*

While auditing that gate (TASK-103), a **second, independent defect** was
found: the committed `.claude/settings.json` hardcoded hook command paths to
`/Volumes/Dev/Sites/COPILOT/claude-copilot/.claude/hooks/*.sh` — a mount that
does not exist on this machine (confirmed: no `/Volumes/Dev`, no
`/etc/fstab`, no `/etc/synthetic.conf`, no symlink resolves it; the real
checkout is `/Users/pabs/Sites/COPILOT/claude-copilot`). That meant the fixed
hook logic was wired in config but **could not execute at all** here.

Scope for this memo: with the coordinator's authorization, the path defect
(config only, not hook logic) has been repaired and re-verified. What remains
open is whether that scripted re-verification satisfies condition 1's literal
bar, which asks for a real, owner-driven working session — something no
agent can substitute for by running synthetic payloads.

## 3. The evidence (real, verified today)

**Before the fix** — `.claude/hooks/state/` held only `.gitkeep`, zero
`streak-<session_id>.json` files, despite 3 real commits/sessions in
`claude-copilot` since `77f5cdb0` landed (`7274e6b`, `4e0cd22`, `f65639a`) —
consistent with the hooks never having actually run via the committed
settings.json on this machine.

**The fix** — `claude-copilot` commit `8608e24` (branch
`docs/40-initiatives-migration`, pushed): the four hook command paths in
`.claude/settings.json` changed from `/Volumes/Dev/...` to
`/Users/pabs/Sites/COPILOT/claude-copilot/...`. Path references only —
`$CLAUDE_PROJECT_DIR` was deliberately not reintroduced, since an unexpanded
`$CLAUDE_PROJECT_DIR` reference was half the original April-22 deadlock
mechanism per the root-cause doc; absolute paths were the repo's own,
already-settled fix for that half.

**Post-fix scripted verification:**
- `tests/hooks/test-pretool-check.sh`: **48/49 passed** — the 1 failure is
  the doc's own documented pre-existing `<50ms` performance-timing flake,
  unrelated to this change.
- `pretool-check.sh` invoked standalone at its corrected absolute path,
  reproducing both doc scenarios exactly: (a) 5 consecutive main-session
  `Read` calls → 5th denied with the expected reason; (b) main session reads
  4, delegates, subagent reads 7 more (`agent_type` set) → **0 denials**,
  streak state ends at `4` (only main-session reads counted), and the
  parent's own next `Read` is still correctly denied — no cross-
  contamination either direction.
- `session-start.sh`, `user-prompt-submit.sh`, `subagent-stop.sh` invoked
  standalone: all exit `0`, no deadlock, no hang.
- All smoke-test-generated state (`streak-smoketest-*.json`, temporary
  `qa-gate.json`/`session-turns.json` entries) was removed afterward — these
  are gitignored, ephemeral, session-local files; nothing was left to
  pollute real telemetry.

**What this evidence does *not* establish:** a scripted standalone invocation
is not the same event as Claude Code itself driving the hook through a real
interactive session — different code path, no real permission-prompt
interplay, no real multi-tool real-world sequencing, no chance for an
unanticipated event shape to surface. Condition 1 as written asks for the
latter specifically, and it still hasn't happened.

## 4. Options and consequences

**A. Treat the scripted re-verification as satisfying condition 1, roll out
now.** *Consequence:* C-3 proceeds today to the three applicable consumer
repos (`knowledge-copilot`, `cli-copilot`, `copilot-control-tower`; excludes
`codex-copilot`, out of scope — no `.claude/agents`/`.claude/settings.json`
there). Risk: if some real-session-only failure mode exists that the replay
suite and standalone invocation didn't cover, it now surfaces simultaneously
across 3 repos instead of being caught once, in the source repo, first.

**B. Hold — the owner runs one real Claude Code session in `claude-copilot`
doing ordinary work, then rules.** *Consequence:* delays rollout by one
normal working session; converts condition 1 from "not yet attempted" to
"actually attempted," which is the gate's literal intent. If the session
surfaces an unexpected deny, it's caught in the one repo built to absorb it,
not the three about to inherit it.

**C. Do nothing / defer indefinitely.** *Consequence:* the observability
substrate (PostToolUse event ledger for W-2's per-solution token accounting,
DEC-2's zero-mechanical-enforcement finding) stays unmeasured everywhere but
`claude-copilot`; TASK-103 stays `blocked`.

## 5. Recommendation (advice, not a ruling)

**Hold (Option B).** The path defect was a real, mechanical blocker and is
now fixed; the scripted verification is thorough and matches the doc's own
proof bar. But condition 1 was written the way it was specifically to catch
what synthetic replay can't — and given this hook system's own history (a
fix that looked complete on 2026-04-22 and silently wasn't, for two months),
the cheap, honest move is to actually clear the bar as written rather than
argue it's close enough. One normal session costs little; rolling out to
three repos and finding a real-session-only surprise there costs more.

## 6. Exact one-line actions

- **Hold (recommended):** start one real Claude Code session in
  `/Users/pabs/Sites/COPILOT/claude-copilot`, do normal work, then check
  `.claude/hooks/state/streak-*.json` exists with sane values and no
  unexpected `hook-deny` — then rule: `tc task update 103 --status in_progress`
  (ready to widen) or file a new fix-and-retry note if a denial surprises you.
- **Roll out now (Option A):** `tc task update 103 --status in_progress
  --metadata '{"condition_1":"waived-by-scripted-verification"}'` then hand
  to `@agent-do` to widen the matcher in `knowledge-copilot`, `cli-copilot`,
  and `copilot-control-tower`.
- **Do nothing:** `tc task update 103 --status blocked --metadata
  '{"decision":"deferred"}'` (current state).
- **Re-run the scripted verification yourself:** `cd
  /Users/pabs/Sites/COPILOT/claude-copilot && bash
  tests/hooks/test-pretool-check.sh`
