# DEC-2 — Protocol declaration: enforce, simplify, or retire

> tc task: **TASK-113** (R-3, `phases/phase-3-soul-remediation.md`) · Claim:
> `protocol-declaration-rate-baseline` (`claims.yaml`) · Status: prepared,
> **not ruled** — owner decides. This memo is TASK-113's deliverable.

## 1. The decision, in one sentence

Sessions are supposed to open every main-session reply with a
`[PROTOCOL: ...]` declaration; almost none do, and the code shows why —
nothing checks for it — so decide whether to build a mechanical check,
shrink what the declaration requires, or drop the requirement.

## 2. Context, in plain language

`claude-copilot/.claude/commands/protocol.md` defines the `/protocol`
workflow: detect what kind of work a request is, route it through a
specific chain of specialist agents, and prefix every response with a
one-line declaration of what's happening (`[PROTOCOL: EXPERIENCE | Agent:
@agent-sd | Action: INVOKING]`). This is meant to be the visible signal that
the framework's routing discipline is active. The April 2026 diagnostic
found it barely happened (3.5%) and hoped hooks would fix it. They didn't.

## 3. The evidence (real numbers, quoted with source)

**Source:** `tools/cse-bench/output/transcripts-latest.json`,
`generated_at: 2026-07-13T18:23:39Z`, `metrics.global` block. Regenerated
in this session against the live transcript corpus (248 `.jsonl` files, 26
main sessions).

| Definition | Median | Mean | n (sessions) |
|---|---|---|---|
| Loose (`protocol_declaration_rate_loose` — any main-session assistant message) | **0.0%** | 7.15% | 22 |
| Strict (`protocol_declaration_rate_strict` — first reply to a user turn only) | **0.0%** | 0.0% | 15 |

For comparison, the previously registered figure (`claims.yaml`,
`protocol-declaration-rate-baseline`, last checked 2026-07-12) states
"median ~0.8–0.9% under the all-messages definition, 0.0% under strict" —
this is the number the task title's "0.9%" comes from. **Today's re-run
shows the loose median at literal zero, not 0.9%** — meaning more than half
of sessions in the current corpus have zero protocol declarations at all,
not a small trace of them. The mean (7.15%) is pulled up by a small number
of sessions that do use it; the median is what most sessions actually do,
and that is nothing. The strict definition (first reply to a user turn,
arguably the only place the declaration is meaningful) is **flat zero
across every one of 15 sessions measured**.

**Why, mechanically (verified directly against the code, not inferred):**
- `protocol.md` (the `/protocol` command file itself) is **31,910
  characters (~7,978 tokens, chars/4 heuristic)** — this is the payload the
  session pays *if and only if* someone types `/protocol` explicitly, which
  the numbers above show almost never happens.
- `protocol-injection.md` (the file actually auto-injected via the
  `SessionStart` hook per `session-start.json`) is **3,445 characters
  (~861 tokens)** and fires **once per session**, not per turn — this part
  already respects the SOUL rule that enforcement "pays once, never
  per-turn." So the recurring cost per turn is not the problem.
- `.claude/hooks/user-prompt-submit.sh` (258 lines, the `UserPromptSubmit`
  hook — the one place a per-turn check could live) contains **zero**
  references to "protocol" of any kind. **There is no mechanical check
  anywhere in the hook pipeline that verifies a response starts with the
  declaration.** The requirement exists only as an instruction inside
  `protocol.md`'s "Your Obligations" section ("Every response MUST start
  with a Protocol Declaration") — nothing enforces it, and nothing warns
  when it's skipped.

This directly answers phase-3 R-3's own diagnostic question — "is
`/protocol` too heavy for real turns, or unenforced?" — **it's unenforced**,
not (per-turn) heavy. The heavy artifact (`/protocol`'s ~8k-token command
file) is rarely paid for precisely because adoption is near zero.

**Caveat:** single-author data (one person's session corpus); no
external-pilot signal yet.

## 4. Options and consequences

**Option A — Enforce.** Add a check (e.g. in `user-prompt-submit.sh` or a
new lightweight `Stop`/`PreToolUse` check) that verifies the first line of a
main-session response matches the declaration grammar, warns on miss, and
optionally blocks after N misses. *Consequence:* real adoption becomes
measurable and improvable, but building and tuning a false-positive-free
regex/parser against natural assistant text carries its own risk — a
brittle check either nags constantly (workflow friction) or silently misses
real violations (false confidence). No hook currently exists to build from;
this is new work, not a toggle.

**Option B — Simplify.** Shrink the declaration requirement itself — e.g.
drop the full `[PROTOCOL: TYPE | Agent: @agent-X | Action: Y]` grammar for
something closer to the delegation-rate signal already measured
elsewhere (`delegation_rate_tool_share`/`delegation_rate_event_share`,
already `passing` in the register), so the behavior that actually matters
(is work being delegated to specialist agents at all) is tracked directly
instead of through an easy-to-forget prefix convention. *Consequence:*
loses the specific "which flow, which agent, what action" texture the
current declaration carries, but aligns the measured signal with a metric
that's already proven to move (tool-share delegation is at ~40%, an order
of magnitude better than protocol declaration).

**Option C — Retire.** Remove the "every response declares" obligation from
`protocol.md`/SOUL, and rely solely on delegation-rate as the adoption
signal. *Consequence:* is the honest option if the declaration was always a
proxy for delegation rather than a thing worth measuring on its own — but it
also removes the only visible per-turn evidence a session is following ANY
structured flow at all, which matters for a human skimming a transcript.

**Do nothing:** leave the claim `failing`, the requirement in place,
unenforced. *Consequence:* the gap between stated obligation and actual
behavior stays on record (honest), but nothing changes and the same
diagnostic will re-run the same way next quarter.

## 5. Recommendation (advice, not a ruling)

This is advice, not a ruling: Option C (retire the declaration-prefix
requirement specifically, not the underlying routing discipline) fits the
evidence best. The declaration was meant as a visible proxy for "is the
framework's routing discipline active" — but this program already has a
directly-measured, `passing` proxy for that (delegation rate,
`delegation-rate-baseline`, tool-share median ~40.5–40.9%). Keeping a
second, unenforced, near-zero-adoption proxy alive mostly adds a stale claim
to the register without adding information. If the owner wants the visible
per-turn signal kept for human readability (not measurement), Option B
(a shorter, cheaper-to-comply-with declaration) is the fallback worth
choosing over Option A, since Option A requires building new enforcement
infrastructure to chase a signal that has a working substitute already.

## 6. Exact one-line actions

- **Option A (enforce):** `tc task update 113 --status in_progress --metadata '{"decision":"enforce"}'` then hand TASK-113 to `me` to add a protocol-declaration check to `user-prompt-submit.sh`.
- **Option B (simplify):** `tc task update 113 --status in_progress --metadata '{"decision":"simplify"}'` then hand TASK-113 to `ta` to draft the reduced declaration grammar.
- **Option C (retire):** `tc task update 113 --status in_progress --metadata '{"decision":"retire"}'` then hand TASK-113 to `doc` to strike the obligation from `protocol.md` and SOUL, citing `delegation-rate-baseline` as the retained signal.
- **Do nothing:** `tc task update 113 --status blocked --metadata '{"decision":"deferred"}'`
- **Re-run this evidence:** `cd tools/cse-bench && python3 cse_bench.py collect --only transcripts`
