# DEC-5 — Configure-or-cut: fireflies, reddit, metabase, method

> **RULED 2026-07-14 (in-conversation, explicit authorization):** CUT
> fireflies and reddit; FINISH the metabase cut already ruled 2026-06-29;
> CUT the method credentials (no build). Also folds in DEC-9 3a/4b's
> `notion` finding (same shape as metabase/method) — CUT. **EXECUTED in
> cli-copilot commit `ba99edb`:** removed
> `copilot_cli/services/{fireflies,reddit}/` (code + tests + docs entry +
> `main.py` registrations + `Settings` fields), removed the empty
> `copilot_cli/services/{metabase,notion}/` directories (stale
> `__pycache__` only, no source), removed `METABASE_API_KEY`,
> `NOTION_API_KEY`/`NOTION_N8N_ID`, and all `METHOD_COPILOT_*` from local
> `.env` (gitignored, not in the commit) and `.env.example`. Conformance
> suite's `KNOWN_GAPS` table is now empty; suite went from 135
> passed/3 xfailed to **126 passed, 0 xfailed** (fewer total cases because
> 2 services' per-criterion parametrized cases are gone, not because
> anything newly fails). Full pytest suite: 1741 passed/16 skipped (was
> 1808/16/3-xfailed). `ruff check`/`ruff format --check` clean for
> everything in the commit. Pushed; CI green (run `29339409881`).
> **Outstanding, owner-only:** revoke `METABASE_API_KEY` at the Metabase
> admin console (never done, confirmed still live) and re-verify
> `NOTION_API_KEY` is actually dead at Notion — a separate initiative doc
> (`docs/initiatives/infisical-rollout/01-secrets-rotation-worklist.md`)
> claimed on 2026-06-29 it was "already deleted by Pablo," but the value
> was still physically present, non-empty, in `.env` until this session;
> that doc has been corrected in place (same commit) rather than left
> contradicting this record. TASK-122/TASK-120 marked `completed`.

> tc task: **TASK-122** (R-13, `phases/phase-3-soul-remediation.md`) ·
> Claim: `cli-soul-conformance` (`claims.yaml`) · Status: prepared, **not
> ruled**. **Nothing has been cut, configured, or deleted.** This ruling
> also unblocks R-11's skipped conformance gaps (TASK-120) and feeds B-17
> (TASK-100).

## 1. The decision, in one sentence

Four CLI Copilot service surfaces are structurally dead in different ways
(no credentials, empty implementation, or credentials with no code at all)
— decide, per service, whether to finish configuring it or cut it, since
the conformance suite is deliberately leaving these three gaps open until
this is ruled.

## 2. Context, in plain language

CLI Copilot's own SOUL-conformance test suite treats "a service exists but
doesn't meet the quality bar" as a tracked, visible failure (`xfail`), not
a silent pass. Per the relevance rule adopted 2026-07-13 ("don't polish
surface that may be removed"), the suite intentionally leaves these four
services' gaps un-fixed rather than investing more engineering time in
surface that this decision might delete. That means the suite's remaining
red is now *entirely* this decision's fault, in a good way — closing R-13
either finishes these services properly or removes the code, and either
path clears the suite to fully green.

## 3. The evidence (real, verified today — not from the register)

**The conformance suite, run live in this session** (`cli-copilot`,
`CC=/usr/bin/cc PATH=/usr/bin:$PATH uv run --extra dev pytest
tests/test_soul_conformance.py -q --tb=no -rxX`, 2026-07-13):

```
135 passed, 3 xfailed in 5.66s
```

All **3** remaining `xfail` cases are scoped to fireflies/reddit
specifically (verified against `tests/test_soul_conformance.py`,
`KNOWN_GAPS`, last touched by commit `7a76f80` on 2026-07-13):

| Service | Criterion | Gap |
|---|---|---|
| fireflies | `config_documented` | `FIREFLIES_API_KEY` not documented in `.env.example` |
| reddit | `config_documented` | `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`, `REDDIT_USER_AGENT` not documented in `.env.example` |
| fireflies | `docs_entry` | no `docs/services/*.md` entry exists for fireflies |

This is a real, current improvement worth noting plainly: `claims.yaml`
(`cli-soul-conformance`, last checked 2026-07-12) recorded **125/138
passing, 13 tracked gaps**. Today it's **135/138, 3 tracked gaps** — the
other **10** gaps (the infisical test file, the coolify/infisical error-
hierarchy migration, other docs entries, other undocumented env vars) have
already been closed by the mechanical R-11 wave, exactly as the relevance
rule intended: fix everything except what this decision might delete.
**Closing this one decision is now the only thing standing between CLI
Copilot and a fully green conformance suite.**

**Per-service state (verified directly against the repo, values not
printed — presence/absence and code state only):**

| Service | Code exists? | Credentials configured? | Docs entry? | Notes |
|---|---|---|---|---|
| **fireflies** | Yes (`client.py`, `commands.py`, a test file) | **No** — `FIREFLIES_API_KEY` absent from `.env` | No | Live, registered CLI service with no way to authenticate. |
| **reddit** | Yes (`client.py`, `commands.py`, a test file) | **No** — `REDDIT_CLIENT_ID`/`REDDIT_CLIENT_SECRET` absent from `.env` | Yes (`docs/services/21-reddit.md`) | Docs tell a user to add these vars to `.env`, but `.env.example` itself doesn't list them — the doc and the template disagree. |
| **metabase** | **No** — `copilot_cli/services/metabase/` contains only a stale `__pycache__`, no client/commands code | **Yes** — `METABASE_API_KEY` is present and **non-empty** in `.env` | No | Not registered in `main.py` at all — not even part of the 138-case suite. **Already ruled once**: commit `c8a682c5` (2026-06-29, "scope down Infisical rollout — remove dead notion/metabase") explicitly removed the metabase client/commands/tests/docs, calling it "unused." That removal was **incomplete** — 2+ weeks later, the empty directory remains and the API key was never revoked from `.env` as the commit intended. |
| **method** | **No** — no `services/method/` directory anywhere in cli-copilot, not registered in `main.py` | **Yes** — `METHOD_COPILOT_BASE_URL`, `METHOD_COPILOT_API_KEY`, `METHOD_COPILOT_AGENT_API_SECRET_KEY` are all present and non-empty in both `.env` and `.env.example` | No (no service to document) | Credentials exist for a real ecosystem product (`method-copilot`, Layer 3 in `ECOSYSTEM.md`) that CLI Copilot has never built integration code for. This isn't a dead service being cleaned up — it's a service that was never built despite the credentials being provisioned. |

**Usage evidence — there isn't any, and that's worth stating plainly.**
CLI Copilot ships an opt-in usage ledger (`COPILOT_USAGE_LOG`,
`copilot_cli/shared/usage_ledger.py`) but it has never been enabled on this
machine: `~/.copilot-cli/usage.jsonl` does not exist. No per-service
invocation counts exist for any of these four. The only corpus-wide signal
available (`tools/cse-bench/output/transcripts-latest.json`,
`generated_at: 2026-07-13T18:23:39Z`, `metrics.global.cli_invocation.by_class`)
shows just **16** total CLI-Copilot-attributable invocations across the
entire measured session corpus (`cli_copilot_unambiguous`: 9,
`cli_copilot_bare`: 7) — not broken out by service, and consistent with
Phase 1's ecosystem-wide finding of "~12 invocations in 1.5y." There is no
way, from any data source available today, to say whether fireflies,
reddit, metabase, or method specifically have ever been invoked by anyone.
**Caveat:** single-author data; no external-pilot usage evidence exists yet.

## 4. Options and consequences (per service)

**fireflies — configure or cut.** *Configure:* add `FIREFLIES_API_KEY` to
`.env.example`, write the missing docs entry, and actually obtain/set a key
so the service is usable. *Cut:* remove `copilot_cli/services/fireflies/`,
its test, its `main.py` registration and health check — same pattern as the
metabase removal commit. *Consequence either way:* closes both fireflies
`xfail` cases; cutting also removes the `docs_entry` gap by removing the
need for docs at all.

**reddit — configure or cut.** *Configure:* add the three env vars to
`.env.example` (the docs entry already exists and already tells users to
set them — this is the cheaper of the two "configure" options here).
*Cut:* remove `copilot_cli/services/reddit/`, its test, its docs entry
(`21-reddit.md`), and its `main.py` registration. *Consequence:* configuring
is nearly free (one `.env.example` edit) if the service is otherwise
wanted; cutting removes a maintained doc page that currently gives correct
setup instructions.

**metabase — finish the cut already ruled, or reverse it.** *Finish the
cut:* remove the empty `copilot_cli/services/metabase/` directory
(including the stale `__pycache__`) and revoke/remove `METABASE_API_KEY`
from `.env`, completing what commit `c8a682c5` started. *Reverse it:*
re-implement the metabase client/commands from scratch, since credentials
are already provisioned and non-empty. *Consequence:* finishing the cut is
low-cost cleanup with no functional change (the service has been
non-functional since June); reversing means rebuilding a service that was
explicitly called "unused" three weeks ago, without any new evidence of
demand since then.

**method — configure (build it) or cut the credentials.** *Configure:*
build the `services/method/` integration CLI Copilot never shipped,
consuming the already-provisioned credentials. *Cut:* remove the
`METHOD_COPILOT_*` entries from `.env`/`.env.example` since there is no
code that reads them. *Consequence:* configuring is real, net-new
engineering work (there is nothing to finish, only to start); cutting is a
config-only change that removes credentials sitting unused with no
consumer, closing an unnecessary secret-surface exposure.

**Do nothing (all four).** *Consequence:* the CLI conformance suite's 3
remaining gaps stay open indefinitely (they were deliberately left there
for this decision); R-11/TASK-120's skipped scope stays skipped; B-17's
delete-or-defend list has nothing to act on for these four; `method`'s
unused, unconsumed credentials keep sitting in `.env`/`.env.example`
regardless.

## 5. Recommendation (advice, not a ruling)

This is advice, not a ruling, service by service:
- **fireflies, reddit:** cut, on current evidence — zero usage signal
  (opt-in ledger never enabled, no way to distinguish these from the
  ecosystem's ~12-invocations-in-1.5-years baseline), no credentials
  configured for either, and cutting removes real gaps at effectively zero
  cost since neither is currently usable anyway.
- **metabase:** finish the cut already ruled on 2026-06-29 — there is no
  new argument for reversing a decision made three weeks ago on the same
  "unused" basis; the outstanding work is cleanup (delete the empty
  directory, revoke the leftover key), not a fresh decision.
- **method:** cut the unused credentials rather than build the service —
  building net-new integration work for a service with no measured demand
  runs against this program's own removal rule ("surface that moves no
  outcome bar... gets nominated for deletion"); if `method-copilot`
  integration is wanted later, it should be built when there's a real job
  driving it, not because credentials happen to already exist.

## 6. Exact one-line actions

- **fireflies — configure:** `tc task update 122 --status in_progress --metadata '{"fireflies":"configure"}'` then hand to `me` to add `FIREFLIES_API_KEY` to `.env.example` and write `docs/services/*.md`.
- **fireflies — cut:** `tc task update 122 --status in_progress --metadata '{"fireflies":"cut"}'` then hand to `me` to remove `copilot_cli/services/fireflies/` + its test + its `main.py` registration.
- **reddit — configure:** `tc task update 122 --status in_progress --metadata '{"reddit":"configure"}'` then hand to `me` to add the three env vars to `.env.example`.
- **reddit — cut:** `tc task update 122 --status in_progress --metadata '{"reddit":"cut"}'` then hand to `me` to remove `copilot_cli/services/reddit/` + its test + `docs/services/21-reddit.md` + its `main.py` registration.
- **metabase — finish the cut:** `tc task update 122 --status in_progress --metadata '{"metabase":"finish-cut"}'` then hand to `me` to `rm -rf copilot_cli/services/metabase/` and remove `METABASE_API_KEY` from `.env`/`.env.example`.
- **metabase — reverse (rebuild):** `tc task update 122 --status in_progress --metadata '{"metabase":"rebuild"}'` then hand to `ta` for a fresh implementation plan.
- **method — cut credentials:** `tc task update 122 --status in_progress --metadata '{"method":"cut-creds"}'` then hand to `me` to remove `METHOD_COPILOT_*` from `.env`/`.env.example`.
- **method — configure (build):** `tc task update 122 --status in_progress --metadata '{"method":"build"}'` then hand to `ta` for an implementation plan consuming the existing credentials.
- **Do nothing:** `tc task update 122 --status blocked --metadata '{"decision":"deferred"}'`
- **Re-run the conformance scorecard:** `cd /Users/pabs/Sites/COPILOT/cli-copilot && CC=/usr/bin/cc PATH=/usr/bin:$PATH uv run --extra dev pytest tests/test_soul_conformance.py -q --tb=no -rxX`
