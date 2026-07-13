# DEC-3 — Ratify the SOUL §3 correction (strike the falsified "~94%")

> tc task: **TASK-114** (R-5, `phases/phase-3-soul-remediation.md`) · Claim:
> `framework-externalization-94pct` (`claims.yaml`) · Status: prepared,
> **not ruled** — owner ratification is the gate.

## 1. The decision, in one sentence

`claude-copilot/SOUL.md` still states "~94% less context for externalized
work products vs inlining" in three places; the measurement behind that
number is falsified and inverted, the README was already corrected, and the
SOUL text needs the same correction, formally logged as a §10 amendment —
ratify it.

## 2. Context, in plain language

SOUL §3 ("Design Principles," Principle 3: "Context Is the Budget") makes a
specific, falsifiable claim: delegating work to agents and storing the
detail as work products, instead of inlining it into the main
conversation, saves "~94% less context." This program built the first
actual measurement of that claim. It isn't just unproven — it's the
opposite of true under the measurement taken. The README (a lower-stakes,
easier-to-edit surface) was already corrected on this basis. SOUL is the
harder, more formal document — per its own §10 ("Evolution"), SOUL changes
only when "we learn something durable that contradicts a current
principle," logged in a changelog. This is exactly that case, and the
correction needs the owner's ratification per that section's own rule, not
a silent edit.

## 3. The evidence (real numbers, quoted with source)

**Primary evidence — the registered, committed finding**
(`claims.yaml`, id `framework-externalization-94pct`, `last_checked:
2026-07-12`, evidence field `tools/cse-bench/output/framework_soul-latest.json`):

> "Externalized work products yield '~94% less context' vs inlining
> (claude-copilot SOUL §3 Principle 3, README panel). **FALSIFIED AND
> INVERTED** under population measurement: agent returns median **658**
> tokens vs WP content median **217** — returns are **~3x LARGER** than the
> artifacts they externalize."

**README already corrected — verified directly, not assumed:**
`git -C /Users/pabs/Sites/COPILOT/claude-copilot show --stat 7274e6b`
confirms commit `7274e6bfd990fd3b7f1837b38f83fdc6ac97f6b7` ("Strike the
'~94% less context' claim — falsified by measurement," 2026-07-12
20:33:24 -0400): `README.md | 8 ++++----` (4 insertions, 4 deletions). The
commit message states the panel "now states the mechanism without the
number" and explicitly flags "SOUL §3's own quotation of the figure... for
owner-ratified §10 correction" — i.e. this exact decision was already
anticipated at correction time.

**SOUL.md still quotes the figure — verified directly, today, three
places:**
- Line 84 (§3, Principle 3 itself): *"agents return ~100 tokens, not their
  full reasoning"* — precedes *"(~94% less context for externalized WPs vs
  inlining)"*.
- Line 178 (§5, Feature Filter table): *"~94% less context for externalized
  WPs vs inlining above the threshold."*
- Line 231 (§7, Voice & Tone, Language Rules table): lists "~94% less
  context for externalized work products" as an example of language the
  project *should* say (i.e. the table itself models using the false
  figure as good voice).
- §10 (Evolution changelog) has no entry for this correction yet; the last
  entry is 2026-06-28 (v1.0 ratification).

**This session's attempt to re-run the measurement:** re-running
`cse_bench.py collect --only framework_soul` today produced
`tools/cse-bench/output/framework_soul-latest.json`
(`generated_at: 2026-07-13T18:26:30Z`) with
`metrics.externalization_ratio.verdict: "unmeasurable (insufficient data
in one or both distributions)"` and `wp_tokens.n: 0`. **This is an
environment gap in this session, not new counter-evidence**: the
`tasksdb`/work-products glob this collector depends on
(`/Volumes/Dev/Sites/COPILOT/*/.copilot/tasks.db`) could not resolve
because `/Volumes/Dev` is not mounted in this sandbox and this session has
no permission to create it (`mkdir /Volumes/Dev` → "Permission denied,"
verified). The 2026-07-12 registered finding above remains the real,
committed evidence; it simply could not be independently reproduced inside
*this* session. The collector's own caveat (unchanged either way) already
notes this is a population-level, not per-item-joined, comparison — stated
plainly in both the 07-12 finding and the collector's code.

## 4. Options and consequences

**Option A — Ratify the correction now.** Add a SOUL §10 changelog entry
(e.g. "2026-07-13 | v1.1 | Struck the falsified '~94% less context' figure
from §3/§5/§7 per `framework-externalization-94pct` measurement (agent
returns median 658 vs WP median 217, inverted); mechanism description kept,
number removed — mirrors README correction 7274e6b") and edit the three
lines identified above. *Consequence:* SOUL and README become consistent
again; the claim can be marked `retired-by-ratification` instead of sitting
`failing` indefinitely; closes out R-5 cleanly.

**Option B — Ratify a rewrite instead of a strike.** Rather than removing
the number, replace it with an honestly-scoped restatement (e.g., state the
mechanism and point to the register for current numbers rather than hard-
coding any percentage in SOUL text at all) so future measurement drift
doesn't require another SOUL edit each time the numbers move. *Consequence:*
slightly more editorial work now, but avoids a repeat of this exact problem
if `agent-frugality`'s numbers (DEC-1) keep shifting.

**Option C — Do nothing.** Leave SOUL quoting the falsified figure.
*Consequence:* README and SOUL now actively contradict each other (one
struck, one still claiming it) — this is worse than SOUL never having been
corrected, because it makes the inconsistency itself visible to anyone
comparing the two documents, and the claim stays `failing` with no path to
resolution.

## 5. Recommendation (advice, not a ruling)

This is advice, not a ruling: given the SOUL principle's own text already
separates the *mechanism* ("agents return ~100 tokens, not their full
reasoning") from the *number* ("~94% less context"), Option B (rewrite to
state the mechanism and defer to the register for the number, rather than
re-hardcoding a new percentage) costs little more than Option A's straight
strike and avoids the exact failure mode that put SOUL in this position —
a number frozen in a document that measurement later moved past. Whichever
option is picked, DEC-1's own evidence (median return now 1,032 tokens, not
658) shows the underlying numbers are still moving, which is itself an
argument against re-hardcoding any specific percentage into SOUL text.

## 6. Exact one-line actions

- **Option A (ratify strike):** `tc task update 114 --status in_progress --metadata '{"decision":"ratify-strike"}'` then hand TASK-114 to `doc` to add the SOUL §10 changelog entry and edit lines 84/178/231.
- **Option B (ratify rewrite):** `tc task update 114 --status in_progress --metadata '{"decision":"ratify-rewrite"}'` then hand TASK-114 to `doc` to draft the mechanism-only restatement for owner sign-off before editing SOUL.
- **Do nothing:** `tc task update 114 --status blocked --metadata '{"decision":"deferred"}'`
- **Re-verify the README correction:** `git -C /Users/pabs/Sites/COPILOT/claude-copilot show --stat 7274e6b`
- **Re-attempt the live re-measurement (needs `/Volumes/Dev/Sites/COPILOT` mounted):** `cd tools/cse-bench && python3 cse_bench.py collect --only framework_soul`
