# DEC-9 — Consolidated delete-or-defend list, per product (B-17)

> **RULED 2026-07-14 (in-conversation, explicit authorization):** all of
> DEC-9's cross-referenced items EXECUTED per their originating memos —
> `cpa`/`cs`/`04-shared-systems` design-notes (DEC-8), fireflies/reddit/
> metabase/method/**notion** (DEC-5, `notion` folded into TASK-122's scope
> exactly as this memo's §4b recommended), `frosty-perlman` worktree
> (DEC-4), and the 3 registry-flagged dormant repos below. `kc` held per
> DEC-8 (investigate, not cut). The 13 no-coverage products (§4a) were
> **not** touched — correctly left defend-by-default, no new evidence
> arose for any of them this session. See DEC-4/DEC-5/DEC-8's own RULED
> blocks for exact commits; not re-quoted here.
>
> **EXECUTED — 3 dormant repos (§4c), verified live before archiving (not
> just trusting the registry's prior recommendation):** `gh repo view`
> confirmed none had recent activity — `workflow-copilot` last pushed
> 2025-08-26 (~11 months stale), `ops-copilot` last pushed 2026-01-13
> (~6 months stale, not empty), `ops-copilot-platform` last pushed
> 2026-01-09 and **confirmed empty** (`isEmpty: true`), matching the
> memo's description exactly. All 3 archived via `gh repo archive`
> (reversible — `gh repo unarchive` if ever needed). No repo showed
> activity that would have warranted stopping.
>
> TASK-100 marked `completed`.

> tc task: **TASK-100** (B-17, `phases/phase-4-outcome-program-prd.md` §3 W-6
> acceptance + §4 owner-decision-queue row *"R-9 / R-13 / B-17 — all
> deletions: stale clones, dead services, claim/product removals"*) ·
> Source tasks: **TASK-128** (W-6, `collectors/value_density.py`),
> **TASK-122** (R-13), **TASK-118** (R-9) · Claims:
> `removal-review-first-pass`, `agent-eval-coverage`, `cli-soul-conformance`,
> `knowledge-registry-completeness` (`claims.yaml`) · Status: prepared,
> **not ruled**. **Nothing has been deleted, disabled, cut, or archived on
> the basis of this memo.** This memo **cross-references, not duplicates**,
> DEC-4/DEC-5/DEC-8 — it adds the one layer they don't cover: the
> ecosystem's actual **registered products** (`knowledge-copilot/ECOSYSTEM.md`),
> not just the CSE's own internal tooling surfaces.

## 1. The decision, in one sentence

Across every registered product/surface the removal rule could apply to —
17 `ECOSYSTEM.md` products (3 layers), 2 shared systems, 3 registry-flagged
dormant repos, 22 `cli-copilot` service groups, 16 `claude-copilot` agents,
10 `knowledge-copilot` top-level areas, and 37 skills — only **9 items**
carry a real delete-leaning signal today (3 agents + 1 knowledge area, both
already ruled on in DEC-8; 4 CLI credential/service orphans already ruled on
in DEC-5; 1 newly-observed 5th orphan of the same shape, `notion`, found
while preparing this list; 3 dormant repos the registry itself already
recommends archiving); **every other registered product — all 13 real
end-user application/work products (convoco, insights-copilot, etc.)
included — defends by default**, because no usage/outcome instrumentation
exists yet to measure them at all, and the removal rule nominates only on a
**measured** zero, never on missing measurement.

## 2. Context, in plain language

The removal rule (`phase-4-outcome-program-prd.md` §0.5): *"anything in the
CSE that does not move an outcome bar within its review window is a removal
candidate... nominations are mechanical; deletions are owner-gated."* W-6's
collector (`value_density.py`) operationalizes this for **four** CSE-internal
surface types — agents, CLI service groups, knowledge areas, skills — and
DEC-8 already reports that review in full. R-9/R-13 (DEC-4/DEC-5) already
cover two specific standing decisions (a stale worktree; four CLI
service/credential orphans). None of DEC-4/5/8 look at the thing
`ECOSYSTEM.md` actually calls a **product** — the 17 real, independently-repo'd
things in Layers 1–3 (claude-copilot, convoco, method-copilot, etc.). This
memo's job, per the B-17 task and its own wording ("delete-or-defend list
**per product**"), is to fold the existing surface-level rulings into one
table **and** extend honest coverage to every registered product the
existing collectors never touch, so the owner has a single place to see
every product's status — not to re-derive or second-guess DEC-4/5/8.

## 3. The evidence, per product

### 3a. Layer 1 — Foundational (4 products)

| Product | Evidence (source + number) | Delete case | Defend case |
|---|---|---|---|
| **claude-copilot** | Agents: 3/16 nominated (`cpa`, `cs`, `kc` — measured 0 subagent invocations each; `tools/cse-bench/output/value_density-latest.json`, `generated_at: 2026-07-13T19:49:45Z`, `errors: []` — same 4 nominations as DEC-8, re-run confirms no drift). Skills: 0/37 nominated, evidence **null** ecosystem-wide (no skill-invocation ledger yet; DEC-8 §3d). | No case against the product itself — it is this audit's own instrument. Sub-surface case: `cpa`/`cs`/`kc` only — see DEC-8 §3a/§4/§5, not reproduced here. | Skills: full defend, absence of instrumentation ≠ evidence of non-use (DEC-8 §2, §3d). |
| **cli-copilot** | 22 service groups: 0 mechanically nominated (usage null ecosystem-wide, `~/.copilot-cli/usage.jsonl` never enabled — DEC-8 §3c); conformance 135/138, 3 xfail (fireflies ×2, reddit ×1) verified live in DEC-5 §3. 3 orphan credentials with **no registered service code at all**: `metabase`, `method` (DEC-5 §3), and a **new 5th** of the same shape found while preparing this list: `notion` (`NOTION_API_KEY`/`NOTION_N8N_ID` present and non-empty in `.env`; `copilot_cli/services/notion/` contains only a stale `__pycache__`; not among the 22 `app.add_typer(...)` registrations in `copilot_cli/main.py`, re-verified today via the same `ast`-based `discover_service_groups()` the conformance suite itself uses). | Product itself: no case (20/22 groups green, in active conformance). Sub-surfaces: fireflies/reddit/metabase/method — see DEC-5, not reproduced. `notion` — see §3f below (new). | 20/22 groups: full defend, no evidence against them (see §3f table). |
| **codex-copilot** | No CSE-bench collector traces this repo at all — `value_density.py`'s 4 surface types are scoped to claude-copilot/cli-copilot/knowledge-copilot only. Honest: **no usage or outcome-bar evidence exists either way.** | None. | Full defend-by-default (removal rule's own text: absence of instrumentation is not evidence of non-use). |
| **product-creation-copilot** | Same: no collector coverage, no evidence. | None. | Full defend-by-default. |

### 3b. Layer 2 — Work (6 products)

| Product | Evidence (source + number) | Delete case | Defend case |
|---|---|---|---|
| **pipeline-copilot** | No coverage; no evidence either way. | None. | Defend-by-default. |
| **n8n-copilot** | No coverage as a *product*. `cli-copilot`'s registered `n8n` service group is conformant/0-nominated, but it is ambiguous whether that traces this specific product or is a generic n8n-API integration — weak signal only, not treated as product evidence. | None. | Defend-by-default. |
| **voice-copilot** | No coverage; no evidence either way. | None. | Defend-by-default. |
| **the-collective** | No coverage; no evidence either way. | None. | Defend-by-default. |
| **project-copilot** | No coverage as a *product* (no O-5 solution-survival data). Its CLI integration surface (`project` → module `project_copilot`) IS one of the 22 traced cli-copilot groups: conformant, 0 nominated, `PROJECT_COPILOT_*` credentials configured (§3f). | None. | Defend-by-default at the product level; the CLI-integration surface is already accounted for in §3f, not a separate finding. |
| **everyone-needs-knowledge-management** | `ECOSYSTEM.md`: *"**ARCHIVED 2026-06-29**... Content migrated to Knowledge Copilot. Successor: knowledge-copilot."* | Already actioned. | N/A — not an open B-17 question; the registry already recorded this decision and executed it. |

### 3c. Layer 3 — Applications (7 products)

| Product | Evidence (source + number) | Delete case | Defend case |
|---|---|---|---|
| **convoco** | No coverage as a *product* (live MCP at `mcp.convocoai.com`, but no O-5/O-8 data exists in this ecosystem's instrumentation yet). Its CLI integration surface (`conv` → module `conversations`) is one of the 22 traced groups: conformant, 0 nominated, credentials configured (§3f). | None. | Defend-by-default; it is the registry's own flagship (⭐), and no evidence anywhere argues otherwise. |
| **insights-copilot** | No coverage as a *product*. Its CLI integration (`insights` → module `insights`) is one of the 22 traced groups: conformant, 0 nominated, credentials configured (§3f). Note: TASK-119 (R-10, phase-3) separately flagged a **version-number contradiction** (2.7.0 vs 2.6.0) for this product — a data-hygiene finding, not a delete/defend signal; not this memo's subject. | None. | Defend-by-default. |
| **research-copilot** | No coverage; no matching CLI service group either. No evidence either way. | None. | Defend-by-default. |
| **method-copilot** | No coverage as a *product*. Its CLI integration was **never built at all** despite provisioned, non-empty credentials (DEC-5 §3, "method" row) — this is a CLI-credential/code-gap finding, not evidence about the product's own real-world usage. | Credential-level only: cut the unused `METHOD_COPILOT_*` entries from `cli-copilot`'s `.env`/`.env.example` (DEC-5's recommendation) — **not** a deletion of the method-copilot product, which is registered active and outside this review's evidence reach. | Product itself: full defend, no product-level evidence exists. |
| **forces-assessment** | No coverage; no evidence either way. (Related asset `drip-copilot` is separately classified — see §3e.) | None. | Defend-by-default. |
| **transformations** | No coverage; no evidence either way. | None. | Defend-by-default. |
| **preflight-copilot** | `ECOSYSTEM.md`'s own registry row: status **"active *(sunset planned)*"** — a pre-existing, owner-recorded signal, not a CSE-bench measurement. | The registry itself already signals this product is winding down. | Still listed "active," still presumably in production until sunset is actually executed. |

### 3d. Shared systems (2, not products per `ECOSYSTEM.md`'s own classification)

| Item | Evidence (source + number) | Delete case | Defend case |
|---|---|---|---|
| **design-system** | `04-shared-systems` knowledge area: 68.8% orphaned (11/16 files), nominated by W-6 (`value_density-latest.json`, DEC-8 §3b) — but this measures **documentation cross-reference inside the knowledge-copilot corpus**, not real usage of the actual Storybook/Vite app itself (which "deploys to `design.ineedacopilot.com`" per `ECOSYSTEM.md`). No evidence exists about the deployed app's own usage. | DEC-8 recommends cutting the stale `PHASE-*-SUMMARY.md` build-phase notes specifically — **not** the design-system product/repo itself (DEC-8 §5). | Orphan-rate is a documented floor, not proof nobody reads the docs directly (DEC-8 §4); the deployed app itself carries zero evidence either way. |
| **platform** | Same `04-shared-systems` area, but DEC-8 explicitly calls platform's 4 files "lower-orphan-risk dev-setup docs and a reasonable keep either way" (DEC-8 §3b, §5). | None — DEC-8's own weakest candidate in the set. | Defend, per DEC-8's own recommendation. |

### 3e. Already flagged by the registry itself (not new B-17 findings)

`ECOSYSTEM.md`'s own "Out of scope / not tracked here" section already
records these — this memo surfaces them for a complete per-product view,
it does not re-derive them:

| Item | Evidence (source) | Status |
|---|---|---|
| **workflow-copilot** | `ECOSYSTEM.md`: "Dormant / recommended for GitHub archival... superseded by n8n-copilot" | Pre-existing registry recommendation, not executed. |
| **ops-copilot** | `ECOSYSTEM.md`: dormant, recommended for GitHub archival | Pre-existing registry recommendation, not executed. |
| **ops-copilot-platform** | `ECOSYSTEM.md`: "(empty repo)", dormant, recommended for GitHub archival | Pre-existing registry recommendation, not executed — an empty repo is about as strong a delete case as exists. |
| **rfp-copilot** | `ECOSYSTEM.md`: archived, superseded by pipeline-copilot | Already resolved. |
| **conversations-copilot** | `ECOSYSTEM.md`: archived, superseded by convoco; DEC-4 already confirmed no stale clone/duplicate exists on this machine under this name. | Already resolved (cite DEC-4). |
| **drip-copilot**, **convoco-site** | `ECOSYSTEM.md`: "Assets, not products" | Out of B-17 scope by the registry's own classification — not a product, no ruling needed here. |

Personal/infra (`admin-server`, `saas-financial-model`) and client-delivery
work (Hermes/Hermes-3/hermes-1, Clio, Beacon Mobility, lars-website) are
explicitly out of scope of the product ecosystem per `ECOSYSTEM.md`'s own
"not tracked here" note — B-17 does not apply to them and this memo does not
extend into that territory.

### 3f. CLI service groups detail (22 registered, traced by W-6/DEC-8; full table, not reproduced elsewhere)

Module identity (the canonical service name per `tests/test_soul_conformance.py`'s
own comment, not the CLI verb), conformance from `cli_soul-latest.json`
(`generated_at: 2026-07-13T19:49:53Z`, `errors: []`) cross-verified against
DEC-5's live pytest run:

| Module (verb) | Conformance | Credentials | Flag |
|---|---|---|---|
| git (`git`) | pass | n/a | none |
| docker (`docker`) | pass | n/a | none |
| shell (`shell`) | pass | n/a | none |
| fireflies (`fireflies`) | **2 xfail** (`config_documented`, `docs_entry`) | not configured | DEC-5 |
| discord (`discord`) | pass | — | none |
| filesystem (`fs`) | pass | — | none |
| system_services (`services`) | pass | — | none |
| postgresql (`db`) | pass | — | none |
| nocodb (`crm`) | pass | — | none |
| brevo (`brevo`) | pass | configured | none |
| n8n (`n8n`) | pass | configured | none |
| document (`docs`) | pass | — | none |
| bi (`bi`) | pass | — | none |
| monitoring (`monitoring`) | pass | — | none |
| coolify (`coolify`) | pass | configured | none |
| infisical (`infisical`) | pass | — | none |
| insights (`insights`) | pass | configured | none |
| project_copilot (`project`) | pass | configured | none |
| conversations (`conv`) | pass | configured | none |
| skill (`skill`) | pass | — | none |
| reddit (`reddit`) | **1 xfail** (`config_documented`) | not configured | DEC-5 |
| uspto (`uspto`) | pass | — | none |

**Not among these 22** (unregistered, orphan-credential surfaces — see §3a/§4b):
`metabase`, `method` (DEC-5), `notion` (new, this memo).

### 3g. Agents & knowledge areas rollup (full detail in DEC-8, not reproduced)

16 agents traced, 3 nominated (`cpa`, `cs`, `kc`); 10 knowledge areas
traced, 1 nominated (`04-shared-systems`); 37 skills traced, 0 nominated
(evidence null ecosystem-wide). See DEC-8 §3a/§3b/§3d for the full
per-surface tables and per-nomination options — deliberately not
re-typeset here.

## 4. Options and consequences

**4a. The uniform case — 13 registered products with zero CSE-bench coverage**
(codex-copilot, product-creation-copilot, pipeline-copilot, n8n-copilot,
voice-copilot, the-collective, project-copilot, convoco, insights-copilot,
research-copilot, method-copilot, forces-assessment, transformations):
- *Defend-by-default (no action):* consequence — these products keep
  existing with no removal pressure; the honest state is "never measured,"
  not "measured unused."
- *Owner asserts direct knowledge instead:* if the owner independently knows
  a product has (or lacks) real users — e.g. Convoco's live MCP — that
  knowledge can override the mechanical null; this memo cannot certify it
  either way and does not attempt to.
- *Do nothing:* same as defend-by-default here — nothing is lost, the next
  review cycle re-measures once W-1 (Outcome Ledger)/W-2 (token joins)/W-4
  (external pilots) exist.

**4b. `notion` orphan credential (`cli-copilot`) — new finding, same shape as DEC-5's `metabase`/`method`:**
- *Finish a cut (same pattern as metabase):* remove the stale
  `copilot_cli/services/notion/__pycache__` directory (no other code exists
  to remove) and revoke/remove `NOTION_API_KEY`/`NOTION_N8N_ID` from `.env`.
- *Build it:* implement the notion integration CLI-copilot never shipped,
  consuming the already-provisioned credentials.
- *Fold into DEC-5/TASK-122 instead of a new decision:* since it is
  structurally identical to `metabase`/`method`, treat it as a 4th (really
  5th, counting `method`) row of that same open decision rather than
  opening a parallel one.
- *Do nothing:* the credential sits unused, unconsumed, same low-grade
  secret-surface exposure DEC-5 already flagged for `method`.

**4c. Registry-flagged dormant repos (`workflow-copilot`, `ops-copilot`, `ops-copilot-platform`):**
- *Execute the registry's own recommendation (archive on GitHub):*
  consequence — closes a housekeeping item the registry already decided,
  at effectively zero cost (each has a named successor or is empty).
- *Keep, no action:* consequence — three already-acknowledged-dormant repos
  remain unarchived indefinitely.

**4d. Everything already covered elsewhere (not reproduced):** `cpa`/`cs`/`kc`
(DEC-8 §4), `04-shared-systems` (DEC-8 §4), fireflies/reddit/metabase/method
(DEC-5 §4), the `frosty-perlman` stale worktree (DEC-4 §4) — same options,
same consequences, cited not repeated.

## 5. Recommendation (advice, not a ruling)

- **13 no-coverage products (all layers): defend-by-default.** This is the
  single largest finding of this consolidated view — most of the
  ecosystem's real, registered products have **zero** usage/outcome
  instrumentation today. That is an honest statement about the state of
  W-1/W-2/W-4, not a statement about whether people use these products.
- **`cpa`, `cs`, `04-shared-systems`'s design-notes: cut** — defer to DEC-8's
  own recommendation, unchanged.
- **`kc`: investigate the delegation-mechanism question first** — defer to
  DEC-8, unchanged.
- **fireflies, reddit, metabase, method: cut** — defer to DEC-5's own
  recommendation, unchanged.
- **`notion`: same treatment as `metabase`** — recommend folding into
  DEC-5/TASK-122's scope and cutting (revoke `NOTION_API_KEY`/`NOTION_N8N_ID`)
  unless the owner actually wants to build the integration; the credential
  has been sitting unconsumed with the same risk profile DEC-5 already
  named for `method`.
- **`workflow-copilot`, `ops-copilot`, `ops-copilot-platform`: execute the
  registry's own already-made archival call** — the lowest-risk,
  zero-new-analysis item in this entire memo.
- **`frosty-perlman` stale worktree: remove** — defer to DEC-4's own
  recommendation, unchanged.
- **`preflight-copilot`: no action from B-17** — flagging only that the
  registry's own "(sunset planned)" note exists, for awareness, since
  sunset execution (if/when it happens) is that product's own process, not
  a CSE removal-rule finding.
- **20/22 CLI service groups, 13 remaining agents, 9 remaining knowledge
  areas, 37 skills, all other products: defend, no action.**

**Caveat (applies to the whole no-coverage set):** single-author corpus; no
external-pilot usage evidence exists yet for any product in this ecosystem.
Re-run this consolidated view once W-1 (Outcome Ledger), W-2 (token/session
joins), or W-4 (external pilots) land real solution/usage records for any of
the 13 currently-uncovered products.

## 6. Exact one-line actions

- **`notion` — finish the cut (fold into DEC-5/TASK-122):** `tc task update 122 --status in_progress --metadata '{"notion":"finish-cut"}'` then hand to `me` to remove `copilot_cli/services/notion/__pycache__` and revoke/remove `NOTION_API_KEY`/`NOTION_N8N_ID` from `.env`.
- **`notion` — build it instead:** `tc task update 122 --status in_progress --metadata '{"notion":"build"}'` then hand to `ta` for an implementation plan.
- **`notion` — do nothing:** `tc task update 122 --status blocked --metadata '{"notion":"deferred"}'`
- **Archive `workflow-copilot`/`ops-copilot`/`ops-copilot-platform` (execute the registry's own recommendation):** `gh repo archive Everyone-Needs-A-Copilot/workflow-copilot && gh repo archive Everyone-Needs-A-Copilot/ops-copilot && gh repo archive Everyone-Needs-A-Copilot/ops-copilot-platform` (run per-repo, owner's own GitHub credentials — not this initiative's to execute unattended).
- **Keep the 3 dormant repos as-is:** no command needed; no action is the same as "keep."
- **For `cpa`/`cs`/`kc`/`04-shared-systems`:** see DEC-8 §6 (not re-quoted here — re-running those commands from this memo risks drifting from DEC-8's own wording).
- **For fireflies/reddit/metabase/method:** see DEC-5 §6.
- **For `frosty-perlman`:** see DEC-4 §6.
- **Re-run the full consolidated view after any of W-1/W-2/W-4 land new product-level evidence:** re-open this memo and update §3b/§3c's "no coverage" rows once a real `tc solution` record or external-pilot result exists for that product.
