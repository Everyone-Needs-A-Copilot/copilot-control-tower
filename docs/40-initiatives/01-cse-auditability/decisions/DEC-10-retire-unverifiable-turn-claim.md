# DEC-10 — Retire the unverifiable April turn-comparison claim

> tc task: **none** (this claim is not gated behind a workstream deliverable
> in the `tc` store — it is a register-hygiene finding surfaced while
> preparing `docs/40-initiatives/01-cse-auditability/decisions/RULING-AGENDA.md`
> §6). Claim: `turn-definition-incompatible-with-april` (`claims.yaml`) ·
> Status: prepared, **not ruled**. **Nothing has been retired.** This memo
> only documents why the claim can never pass and asks the owner to rule on
> retiring it; only the owner rules on removal.

## 1. The decision, in one sentence

`turn-definition-incompatible-with-april` is structurally unable to ever
pass or fail on new evidence — its own `check` field says the comparison it
asks for cannot be performed — so the question isn't "how do we fix it,"
it's "do we retire it, per `t2`'s own rule, or carry it as a claim that can
never move."

## 2. Context, in plain language

Back in April 2026, someone reported a headline "671 turns/session" figure
for how much work happened in a typical session. This program later tried
to check whether that figure is still reproducible under this register's
own, precisely defined `turn` (`claims.yaml` `definitions.turn`: a real
`type=="user"` JSONL record, not a sidechain/meta/tool-result record). It
isn't — a fresh measurement under the current definition returns a median
of 6.0 turns/session, a ~90–112x gap (`phase-1-findings.md` F-6;
`phase-1-reaudit-report.html`, F-6 row: "PARTIALLY REOPENED... Turn-gap
corroborated as a definitional artifact, not a real before/after change").

The claim `turn-definition-incompatible-with-april` was registered to
capture that specific question — "is April's number directly comparable to
(reproducible under) today's `turn` definition?" — as a falsifiable,
re-runnable check, per this program's own V-2 pre-registration discipline.
The problem: the check it names cannot be re-run. April's original counting
script is gone. There is no artifact left that would let anyone recover
April's own operational definition of "turn," which means there is no way
to ever establish whether the two definitions actually agree or disagree —
only that the two *numbers* disagree by two orders of magnitude, which the
re-audit already attributes to a definitional artifact rather than a real
behavior change. The claim, as pre-registered, asks a question that no
longer has an answerable evidence path.

## 3. The evidence (quoting the claim's own check field)

From `claims.yaml` (`id: turn-definition-incompatible-with-april`,
`last_checked: 2026-07-12`):

```yaml
statement: "April 2026's reported '671 turns/session' figure is directly
  comparable to (reproducible under) this register's `turn` definition."
check: "manual — April's original counting script does not exist; nothing
  to re-run"
status: failing
evidence: "docs/40-initiatives/01-cse-auditability/phases/phase-1-findings.md
  (F-6: probe measures median 6.0, a ~100x gap);
  docs/40-initiatives/01-cse-auditability/phases/phase-1-reaudit-report.html
  (F-6 row: 'PARTIALLY REOPENED... Turn-gap corroborated as a definitional
  artifact (~90-112x)')"
```

The `check` field is the load-bearing sentence: *"April's original counting
script does not exist; nothing to re-run."* A claim whose own register entry
states there is nothing left to re-run is, by construction, permanently
unverifiable — not merely currently `failing`. No future session, no
amount of engineering effort inside this program, and no re-audit can
change that fact, because the missing artifact is outside this program's
control (a script that was never preserved, in a doc predating this
initiative).

This program's own T2 truth condition governs exactly this situation
(`claims.yaml`, `t2-no-claim-outlives-its-check`, quoting `phase-2-prd.md`
T2 row verbatim): *"Every public claim in CSE docs maps to a
pre-registered, runnable check; **unverifiable claims are deleted**."* This
claim fails that test on its face — its check is not runnable, and cannot
be made runnable — which is exactly the condition T2's own rule names as
grounds for deletion, independent of any owner ruling on T2 itself (T2
stays open on its own separate, much larger CSE-wide sweep; ruling this one
claim does not close T2).

## 4. Options and consequences

**Option A — Retire it (recommended).** Mark
`turn-definition-incompatible-with-april` `retired-by-unverifiability` in
`claims.yaml`, with an evidence note quoting this memo and T2's rule.
*Consequence:* the register stops carrying a claim that can never move,
which is honest bookkeeping, not score management — retiring an
unfalsifiable claim is not the same category of action as retiring
`framework-externalization-94pct` (DEC-3, retired because the underlying
fact was corrected) or `protocol-declaration-rate-baseline` (DEC-2 Option
C, retired because the obligation it measured was removed). This one is
retired because **the measurement itself is impossible**, which is the
narrowest and least controversial of the three retirement reasons already
in use in this register. The underlying finding (April's number does not
reproduce under a rigorous definition, and the re-audit already
corroborated the gap as definitional) is **not** lost — it stays fully
on record in F-6 (`phase-1-findings.md`, `phase-1-reaudit-report.html`) and
in `definitions.turn`'s own `caveat` field, which already states the
non-comparability plainly. Retiring the *claim* does not retire the
*finding*.

**Option B — Keep it as a permanent red.** Leave `status: failing`
indefinitely, understanding it will never flip. *Consequence:* the
scorecard carries one claim that is, and will always be, red — not because
the ecosystem is broken, but because the yardstick from five months ago no
longer exists to check against. Every future reader of `claims.yaml` has to
re-derive "oh, this one can't ever pass" from the `check` field's prose
each time, rather than the register saying so structurally via a distinct
status. This is the status quo; it is honest but not efficient, and it is
exactly what T2's own rule was written to prevent from accumulating across
the register at scale.

**Option C — Rewrite instead of retire.** Replace the claim with a
narrower, re-runnable one — e.g. *"today's `turn` definition produces a
stable, reproducible median across repeated re-audits"* (which IS checkable
going forward, using only the current definition, no April dependency).
*Consequence:* preserves a *claim slot* about turn-counting stability, but
it is a **materially different claim**, not a fix to this one — silently
narrowing `turn-definition-incompatible-with-april`'s statement to make it
checkable would itself violate V-2 (this program does not silently narrow a
claim to match what's measurable, per the precedent already documented on
`agent-eval-coverage`). If the owner wants this coverage, it should be a
**new**, separately pre-registered claim, not a retroactive edit of this
one.

**Do nothing** (equivalent to Option B): the claim sits `failing` forever,
which is the one outcome every option above, including "keep," agrees is
the thing to actively decide about rather than default into by inaction.

## 5. Recommendation (advice, not a ruling)

**Option A — retire, as `retired-by-unverifiability`.** This is the
cheapest, least controversial ruling in the whole queue: the claim cannot
be fixed by engineering, cannot be fixed by more data, and cannot be fixed
by owner effort of any kind — the only two honest states available are
"retired" or "permanently red by construction," and T2's own
pre-registered rule already names which of those two this program commits
to. The underlying F-6 finding is unaffected either way; only the claim
row's bookkeeping status changes.

## 6. Exact one-line actions

- **Option A (retire):** update `claims.yaml`'s
  `turn-definition-incompatible-with-april` entry —
  `status: failing` → `status: retired-by-unverifiability`, evidence
  appended with: `"Retired per DEC-10 and t2's own rule
  ('unverifiable claims are deleted') — check field confirms April's
  counting script does not exist and cannot be recovered; the underlying
  finding (F-6, definitional turn-gap) remains on record unchanged."`
  (Held for the serialized register-patch pass per this session's
  constraint — not applied directly by this memo.)
- **Option B (keep):** no register edit; optionally
  `tc task create --title "Track: turn-definition-incompatible-with-april stays permanently red" --agent doc --metadata '{"phase":"phase-4","kind":"register-hygiene","decision":"keep-as-permanent-red"}'`
  so the "we decided to keep it" choice is itself on record, not silent.
- **Option C (rewrite as a new claim):** draft a new, separately
  pre-registered claim (e.g. `turn-count-stability-current-definition`)
  before touching this one's status.
