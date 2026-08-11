# HANDOFF: Copilot Control Tower (App Build)

> **⚠️ The build is DONE.** All 9 milestones are built and pushed. If you're
> picking this back up, read [`RESUME-HERE.md`](RESUME-HERE.md) instead: it's the
> post-build pickup (signing, infra, WS-A de-mock). This file is kept for the
> historical build brief only.

> **Model note (read this before the rest):** after this build, an audit found
> the repo's model needed correction (the Copilot Solutioning Ecosystem, CSE).
> See [`docs/10-reference/cse-alignment-decisions.md`](10-reference/cse-alignment-decisions.md)
> and [`docs/10-reference/copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md)
> for the governing model. Two things below are now stated in the corrected
> vocabulary: what this file called "product" (Knowledge/CLI/Claude/Codex) is a
> **component**; "Product/Project" is reserved for a built output, never synced
> by Control Tower (D2). MDM is dropped entirely as a mechanism (D4). Any
> "managed/unmanaged" or forced-MDM-domain language below is historical and has
> been reworded to the corrected invariants. The **code itself** (schema field
> names, verb names, variable names) still says `product` in places; that rename
> is real work, deferred to the build phase, not done by this doc pass.

A self-contained brief to **start a fresh conversation and build the app**. Everything a new session needs with zero prior context. **Point Claude Code at this one file: it carries the full marching orders below.** Supersedes the earlier "freeze WS-A" handoff (the spec is done, the CLI engine is underway), and **the next job is building the actual macOS app.**

> **Kickoff (paste into a fresh Claude Code session in this repo):**
> *"Read `docs/HANDOFF.md` end-to-end and begin: it is your full brief for building Copilot Control Tower."*

---

## ▶ YOUR TASK (Claude Code): read this file end-to-end first, then execute

You've been opened fresh in this repo to **build the app**. This document is your complete starting brief; there is no prior conversation to recover. Do this, in order:

1. **Read the rest of this file end-to-end:** the invariants, the 4×4 model, the engine, milestone 1, and the open decisions.
2. **Then read these (short and load-bearing):**
   - [`SOUL.md`](../SOUL.md): the product's soul + **Feature Filter** (many "obvious" features are deliberately ruled out; check ideas against it).
   - [`CLAUDE.md`](../CLAUDE.md): the 6 invariants, verbatim (they govern everything).
   - The app's design: `docs/product-design/04-experience-design/50-ux-design.md`, `60-ui-design.md`, `70-copy-voice.md`.
   - The contract you parse: `docs/01-architecture/schemas/` + `docs/01-architecture/cli-contract.md` + `error-taxonomy.md`.
3. **Confirm you understand** invariant #1 (*the app parses `cc --json`; it never computes*) and the **4 components × 4 layers, component-first** model.
4. **Then start Milestone 1** (fully specified in "Milestone 1" below): scaffold the Tauri v2 app and get a **real menu-bar tray icon** on screen, wired to `cc doctor --json` on a timer, rendering the **honest status + the component-first dropdown**.
5. **Before writing code, propose the plan and get a nod:** Tauri project layout; the Rust core that spawns `cc` by **absolute, translocation-safe path** (never bare `copilot`); the JSON→state parse; the web-UI dropdown; and **mock-CLI `--json` fixtures** so you can render every state/product/layer during UI dev without a real fleet.
6. **Route the work via `/protocol`** and use the framework agents (ta to plan, me to implement, uid for the web UI, qa to test). Keep the app a **thin skin**: if you catch yourself writing resolution/sync logic in Rust, stop; it belongs in `cc`.

One thing to decide as you pick this up: whether to **push the `ws-a-doctor-slice` branch / open a PR** in `claude-copilot` so the engine is reviewable (it's local-only). The app can be built against the frozen schemas regardless, so this need not block milestone 1.

---

## Where we are (state at handoff)

| | |
|---|---|
| **Repo (app + spec)** | `/Volumes/Dev/Sites/COPILOT/copilot-control-tower`, private, **public at launch** |
| **Spec / design** | ✅ **Complete.** Full PCC product-creation front-end (Phases 1–5) + `SOUL.md` **RATIFIED v1.3** + hardened architecture + parallel PRD + 2 red-teams + versioned `--json` schemas + threat model + test plan + observability/release/OSS/incident/Windows docs. |
| **CLI engine (WS-A)** | 🟡 **5 core verbs built & tested**, on an **unpushed branch** in the *other* repo; see "The engine" below. |
| **The app itself** | ❌ **Not started.** No Tauri code exists yet. **← this is the job.** |
| **Model** | ✅ Corrected & reconciled at the time: **4 components × 4 layers**, component-first (see below). Corrected again since, at the vocabulary level, by the CSE realignment (see the model note above). |

---

## What Control Tower is (30 seconds)

An open-source macOS **menu-bar app** (Tauri v2, single process) that is the **face + supervisor over the `copilot`/`cc` CLI**. It keeps every machine synced and self-healed and gives a non-technical user ("Bob") a working Copilot partner from one double-click. **Two faces, one binary:** Operator mode (end-user client) + Admin mode (IT setup/deploy). A control tower doesn't fly the plane; it monitors, coordinates, clears, and alarms.

**The soul (from `SOUL.md` v1.3):** give a non-technical person the AI superpowers of a deeply technical one, **safely enough to run unattended**, and keep their environment *Copilot-ready*. Trust is earned by **subtraction**; nearly every "obvious" feature (in-app chat, an offline health score, letting Bob self-unblock, `KeepAlive=true`) is a **trust regression**. Read `SOUL.md` before proposing any feature: its Feature Filter rules many out on purpose.

---

## The invariants (never violate; see `CLAUDE.md`)

1. **Parse, never compute.** The app calls `cc doctor/update/repair/resolve/deprovision/freshness/publish --json` and **renders** the result. No resolution/sync/signature/merge/wipe logic in the app. Even the merge-conflict chooser is CLI-computed; the app shows options and passes the choice back.
2. **Single process.** One signed binary = tray + supervisor + scheduler. `launchd` is a **crash-only** watchdog (`KeepAlive={SuccessfulExit:false}`, never `true`). The **CLI** self-serializes via `flock` on `copilot.lock`; the app is *not* the lock.
3. **Never-destroy.** Freely re-materialize `.claude/` and re-clone read-only mirrors; **never** touch a dirty personal working tree. (Consumers only pull; an author's authoring checkout is a protected personal tree; `publish` is additive.)
4. **Security inherited, never weakened.** No `--skip-verify`/`--force`. Security-sensitive config honored **only** via compiled-in trust roots and signed, inherited org/foundation config (a signed capability policy), nothing security-critical comes from user-editable local config. Trust roots are compiled-in code.
5. **Route by actor-competence × reversibility**, auto-act on reversible things the user can't judge; escalate to IT what they can't action; ask the user only non-deferrable decisions about their own data.
6. **One-way inheritance; secrets never travel in it.** Secrets live in the OS keychain and/or a tier-scoped shared secret store whose endpoint is delivered via inherited org repo config (not a secret itself; access stays gated by the user's own GitHub-team membership), never in git; no cross-tier write from a personal-holding path; sync is pull-only/downward; fail-closed leak-scan on writable pushes; git push credentials are always per-user.

**Invoke the CLI by absolute, translocation-safe path: never bare `copilot`** (avoids the `gh copilot` collision).

---

## The model the app renders: 4 components × 4 layers (component-first)

There are **four CSE components** (**Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot**), and **each independently has all four layers**: **foundation → org → department → personal** (foundation is the base; org builds on it; department on org; personal on department). Component is a **config-driven** attribute (the four are the initial set; the UI renders however many exist). ("Product/Project" is reserved for the thing you build *with* these components, e.g. Insights Copilot, and is never synced by Control Tower; see the CSE model note above.)

- **The dropdown is component-first:** worst-wins tray glyph → one honest state sentence → a **component list** (Knowledge / CLI / Claude / Codex), each expandable to its **four-layer health** (which tier is current / behind / repairing).
- **Overrides** resolve nearest-to-you-wins (personal > dept > org > foundation); additive dimensions (e.g. knowledge) **accumulate** across all four.
- The engine already carries `product` on every resolved item and doctor check (schema field name at time of writing, pending rename to `component`), so the app **groups by that field**, then tier. It does not re-derive anything.

> Correction since this was written: the original line here read *"Temporary
> department projects appear as a layer under Department."* That was a vestige
> of the pre-CSE model (a project is never nested inside a component/layer), and
> was later deleted along with its dead UI code (`DeptProjectView`, D8). A
> product/project is self-contained, in its own repo, not a Control Tower layer
> (D10).

Design is in `docs/product-design/04-experience-design/50-ux-design.md` (IA + status-state matrix + a11y), `60-ui-design.md` (the "Air-Traffic Instrument" visual language, tokens, the **aviator-sunglasses tray glyph**, the product-row + four-layer expansion), `70-copy-voice.md` (actual strings, e.g. *"Knowledge Copilot: up to date across all 4 layers"*).

---

## The engine (`cc`): what the app talks to

**Location:** the **`claude-copilot` repo**, `cc` binary (`tools/cc/src/cc/`). WS-A lives here, NOT in this repo (invariant #1: the app consumes it). Branch **`ws-a-doctor-slice`**: **committed, UNPUSHED, not merged.**

Built & tested (pure resolver + thin verbs; `cc/core/ecosystem/{manifest,resolver,dimensions,mirror,materialize,freshness,policy,lockfile,deprovision}.py`):

| Verb | Kind | Notes |
|---|---|---|
| `cc doctor --json` | read | health/status; **false-Healthy is impossible**; checkers carry `product` |
| `cc resolve --explain --json` | read | the pure resolver; items carry `product`, shadow chains, override-stale; security fields **fail-closed** (`null`/`false`) until the verifier lands |
| `cc freshness --json` | read | published `refs/copilot/lock` pointer, one `git ls-remote`; honest `offline` |
| `cc update --json` | **mutating** | reconciling materialize + prune; never-destroy proven; `--dry-run`; fail-closed policy |
| `cc deprovision --json` | **mutating** | wipe disposable trees, retain dirty; `secrets_touched=0`; soft/hard; `--dry-run` |

**To run it:**
```bash
cd /Volumes/Dev/Sites/COPILOT/claude-copilot && git checkout ws-a-doctor-slice
cd tools/cc && uv run pytest        # full suite green
uv run cc doctor --json             # read verbs are SAFE to run live
uv run cc resolve --explain --json
uv run cc freshness --json
```
**Do NOT run `cc update`/`cc deprovision` against your real `~/.claude`:** they mutate; they're only ever exercised in tmp sandboxes. For UI dev, drive the app off **mock `cc --json` fixtures** (the test-plan corpus approach) so you can render every state/product/layer without a real fleet.

**Not built (deliberate):** `repair` (schema is speculative: driven by doctor's repair token, not a real WS-A verb) and `publish` (a separate writable-tier subsystem, not in upstream WS-A scope).

---

## Milestone 1: the app build (the immediate job)

Put the visible thing on the menu bar:

1. **Scaffold Tauri v2** in this repo (Rust core + tiny web UI, no heavy framework; keep the UI small).
2. **Tray icon** (the aviator glyph, worst-wins) that spawns `cc doctor --json` on a timer (by absolute translocation-safe path), parses it in Rust, and renders the honest state. **Never render Healthy unless the JSON says so.**
3. **Component-first dropdown:** the four components, each expandable to four-layer health, driven by real `cc` output, with mock fixtures to populate it during dev.

Then, in order: **Settings** (paste org/dept/personal repo URLs → written into the layer manifest the engine reads), the **first-run wizard** (single self-install path, no MDM zero-touch lane; note its "Claude/Codex/Both" step is still host-framed and should be re-framed component-first), Admin mode (org standup: repos, teams, shared secret store, ecosystem seed; see the CSE model note above; not a fleet-dashboard/MDM center of gravity).

Architecture/PRD context: `docs/01-architecture/architecture.md`, `docs/02-prd/prd.md` (app workstreams WS-B…WS-I), `docs/01-architecture/cli-contract.md` + `docs/01-architecture/error-taxonomy.md` (the contract + exit codes the app parses), `docs/04-validation/test-plan.md` (how to test a parse-never-compute app).

---

## Open decisions & follow-ups (nothing lost)

**WS-A / engine (in `claude-copilot`, branch `ws-a-doctor-slice`):**
- The branch is **unpushed / unmerged**: decide whether to review locally, then push / open a PR (a cross-repo push; get owner go-ahead).
- Persist `product/tier/role` in the lock **write path** (`lockfile.py` has the capability; `update.py`/`materialize.py` don't call it yet).
- Freeze-time confirmations: policy-gate production default (block-all-unverified vs. provisional-trusted-mirror once the signature verifier lands); deprovision soft/hard default + whether it deletes `copilot.lock.json`; per-verb exit-code tables for `update`/`deprovision` (not in `cli-contract.md` yet); `repair` shape (speculative, confirm or drop); `publish` scope (build the separate subsystem or defer).
- **Binary name:** built as `cc`; the contract prose says `copilot`; alias/confirm at freeze.
- **Upstream reconciliation:** the authoritative WS-A contract also lives in `claude-copilot/docs/40-initiatives/01-ecosystem-extensions/{05-control-tower.md,06-control-tower-prd.md}`; `publish` must be added to that PRD; reconcile the schemas into one source of truth at freeze.

**Design / product:**
- The first-run wizard's "Claude / Codex / Both" step is still host-framed; re-frame component-first.
- Shared-vs-per-user credential policy (in `docs/05-security/credentials-and-boundary.md` §5) is a sensible default awaiting owner sign-off.
- `SECURITY.md` needs a real reporting contact (`<!-- TODO -->`).

**Unvalidated (need real users, not code):** the Admin/IT operator experience and the multi-writer authoring flow are **hypotheses** (stamped in the design docs); enterprise scale is aspirational.

**Still-stub docs:** `docs/06-deployment/` was written for a per-MDM (Jamf/Kandji/Intune) walkthrough; that mechanism is dropped (D4). Rework needed: a GitHub-topology + entitlement standup guide (repos, teams, secret store, ecosystem seed) instead.

---

## Commits this session

**`copilot-control-tower` (`main`, pushed to local main):**
`03da786` PCC front-end + soul reframe → `c44cf65` 3 foundational problems + invariant #6 → `a07e389` shared secret store + push-cred seam → `da65370` engineering-doc gaps (schemas/threat-model/test-plan/glossary) → `c1f7c1a` launch docs + AdminContact fix → `bb7e73c` WS-A schema reconciliation → `1ce2401` / `6fe708a` schema honesty fixes → `fa27ed6` **product-first**.

**`claude-copilot` (branch `ws-a-doctor-slice`, UNPUSHED):**
`5dcbdaa` doctor → `6696926` resolve → `211e572` freshness → `ab77cb9` update → `b12840b` deprovision → `ff7d61a` carry `product`.

---

## Practical notes

- **Framework is installed.** Use `/protocol` for disciplined work; framework agents (ta, me, qa, do, doc, sec, sd, uxd, uids, uid, cw, ind, cco) are available; `cc memory search "<topic>"` recalls decisions.
- **Keep the app a thin skin.** If you're writing resolution/sync/merge logic in Rust, stop: it belongs in `cc`.
- **Design is done; don't re-invent it.** The UX/UI/copy for the tray, dropdown, wizard, and Admin mode are specified in `docs/product-design/04-experience-design/`. Build to them.
- **Two follow-up threads live in the other repo** (the `cc` engine); keep the app decoupled: it depends only on the frozen `--json` **contract** (`docs/01-architecture/schemas/`), not the engine's internals.
