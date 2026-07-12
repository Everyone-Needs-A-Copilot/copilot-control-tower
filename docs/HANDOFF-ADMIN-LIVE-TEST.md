# HANDOFF: Admin Mode — Live-Test Ready

**Written 2026-07-12. Branch `app-build`.** This is the current, authoritative handoff for the
Admin-mode work. It supersedes [`HANDOFF-ADMIN-MODE-BUILD.md`](HANDOFF-ADMIN-MODE-BUILD.md), which
describes the pre-redesign mocked prototype and is now historical.

---

## TL;DR — where we are

The Admin-mode redesign is **designed, owner-approved, built, and verified against a mock**. It has
**never run against real GitHub.** The single remaining milestone is the **first live run**, and the
owner is set up to do it.

- All engine logic is proven only by an **offline test suite (137 assertions) against a mock `gh`**.
  Passing tests prove the logic, not real-GitHub behavior. The first live run is itself the test.
- The owner created a disposable real org, **`github.com/Acme-Copilot`**, and this machine is
  confirmed ready to run against it (see [Live-test state](#live-test-state)).
- Testing on a real org has already paid off: pointing at a capitalized org surfaced a real bug
  (uppercase org names, fixed in `401b585`) that 137 mock tests never caught because the mock only
  used lowercase `acme-co`.

**The immediate next action:** run the baton pass against `Acme-Copilot` (see
[How to run the live test](#how-to-run-the-live-test)), then read the terminal narration and the
Setup check and report what really happens.

---

## What this is (product model, in one paragraph)

Copilot Control Tower orchestrates the **Copilot Solutioning Ecosystem (CSE) tooling** across four
inheritance layers (Foundation → Org → Department → Personal), entitled by GitHub repo access.
**Admin mode** is where a technical operator ("Earl") stands up an org's shared spaces on GitHub.
Canonical model: [`docs/10-reference/copilot-solutioning-ecosystem.md`](10-reference/copilot-solutioning-ecosystem.md)
and [`docs/10-reference/four-tier-topology.md`](10-reference/four-tier-topology.md). The six
architectural invariants are in the root [`CLAUDE.md`](../CLAUDE.md); invariant #1
(**parse-never-compute**: the app renders, the engine computes/executes) governs everything below.

---

## Architecture: the baton pass

The redesign's core shape. The app never mutates GitHub; a deterministic engine does, driven by
Claude Code in the terminal; the app then verifies from GitHub truth.

```
 [Control Tower app]                    [Terminal]                      [GitHub]
  teaches + collects                  Claude Code loads the           system of record
  a non-secret brief   ── hand off ─▶  admin-bootstrap skill ──────▶  real repos/teams/
  (never mutates)      (copy command)  → runs the gh engine          grants created
        ▲                                     │                            │
        └──────── Setup check reads GitHub truth (read-only verify) ◀──────┘
```

- **The app** collects an org description, writes a **non-secret brief** (markdown) to
  `~/Library/Application Support/CopilotControlTower/standup-brief.md`, materializes the skill, and
  hands over a copyable command. It runs only read-only local checks and a read-only verify.
- **The engine** (`scripts/admin_bootstrap.sh`) is deterministic, idempotent, additive, never
  destroys, refuses without bypass. It makes **every** existence/idempotency decision (never the
  model). Emits one NDJSON line per step (`created|already-present|updated|skipped|refused|failed`).
- **The skill** (`.claude/skills/admin-bootstrap/`) is the terminal face: reads the brief,
  re-confirms the plan by real repo/team names, teaches auth fixes, runs the engine, narrates.
- **The Setup check** shells the engine's `--verify --json` and renders the result. Truth comes from
  GitHub, never from a claim the terminal made.

Full spec of the machine contract (brief format, handoff command, verify JSON schema, `ecosystem.yml`
2.0, integration registry): [`docs/01-architecture/admin-standup-contract.md`](01-architecture/admin-standup-contract.md).

---

## Commits this cycle (on `app-build`)

Admin work, oldest first:

| Commit | What |
|---|---|
| `651268e` | Approved design: service + interaction design, walkthrough, copy deck, standup contract |
| `65c0ba9` | Engine + skill + offline test suite (initial) |
| `d7afe4d` | Engine: PR-based `ecosystem.yml` delivery + real semver foundation-pin resolution |
| `62212d3` | Native Admin mode rebuilt to the approved 16 surfaces |
| `f1f6687` | Free-plan orgs: branch-protection 403 renders skipped-not-fatal; up-front note |
| `912631e` | Materialized skill invokes the engine by absolute path (baton-pass blocker fix) |
| `5f4842b` | GitHub access requirement surfaced up front (app Prerequisites + new admin doc) |
| `401b585` | Accept real GitHub org names (uppercase allowed); stop deriving the org slug |

**Not part of this handoff:** `cf88977` and `272553e` on the same branch are from a **concurrent
session** (initiatives / auditability governance), unpushed. Do not assume they are admin work.

**Push state:** the admin commits through `401b585` are pushed to `origin/app-build`. The two
concurrent-session commits after it are **unpushed** (left for their owner to handle).

---

## What's real vs mock-only vs stubbed (the honest boundary)

**Real seams (wired, exercised):**
- App: local readiness detection (`gh --version`, `gh auth status`, `command -v claude`), the brief
  writer, skill materialization, and the Setup check's `--verify --json` shell-out.
- Engine: all 137 assertions of logic, **against a mock `gh`**.

**Mock-only (never run against real GitHub):** every mutating path — repo/team/grant creation, base
permission, `ecosystem.yml` write, PR delivery, leak-scan, branch protection. **This is the gap the
live test closes.**

**Honestly-degraded stubs** (marked `// CONTRACT SEAM:` in `native/*.swift`, 11 total; they render
honest empty/degraded states, never fabricated data):
1. **Connect GitHub "are you an owner" row** — no sanctioned local check; permanently "can't check
   from here." (The engine + skill verify ownership for real.)
2. **"Someone left"** (governance) — no per-person team/key lookup implemented.
3. **Org setup live fetch** (governance) — renders from local brief state + a static "None published
   yet," not a live `ecosystem.yml`/registry read.
4. **Handoff header** — always "Not started yet"; the Publisher→Admin schema it needs does not exist.

None of these block the core standup (describe → hand off → create → verify).

---

## Live-test state

Verified on this machine 2026-07-11/12:

| Prerequisite | State |
|---|---|
| `gh`, `jq`, `python3`, `claude` installed | all present |
| `gh` account | `pablitoalejo` |
| `gh` token scopes | `admin:org`, `repo` present (plus `gist`, `workflow`) — sufficient |
| Test org | `github.com/Acme-Copilot` exists, **free plan** |
| Ownership | account is an **owner** (`admin`, active) of Acme-Copilot |

Everything the engine's preflight checks is satisfied. The org is a **disposable throwaway** — the
engine never deletes, so cleanup is manual (delete the org/repos in GitHub when done).

---

## How to run the live test

1. **Launch Admin mode** (from the repo root; the launcher sets the working directory):
   ```
   CT_OPEN_ADMIN=1 scripts/control-tower-tray.command
   ```
2. **Walk the flow:** Orientation → Prerequisites → Contacts → **Connect GitHub** (Check access; the
   ownership row will say "can't check from here" — expected stub) → **Describe your organization**:
   - Org name: `Acme-Copilot` (renders verbatim now, e.g. `Acme-Copilot/codex-copilot`)
   - Harness: Codex or Claude Code
   - Departments: add one or two (e.g. `Accounting`, `Sales`)
   - → Integrations (read-only) → **Secret store: Defer** (simplest first run) → **Review and hand off**
3. **At Review:** copy the command, open a terminal **anywhere**, paste it. Claude Code re-confirms
   the plan by real names, then runs the engine and narrates each repo/team/grant.
4. **Return to the app → Run the Setup check.** Expect green from GitHub truth. On the free plan the
   branch-protection step reports **`skipped`** (paid feature) — correct, not a failure.
5. **Prove never-destroy:** paste the command again → all `Already there`, nothing changes.
6. **Optional:** add a department in the app and hand off again → only the new unit is created.

**Expect to find something.** Every mutating path is mock-proven only; real GitHub (pagination,
permission propagation, exact error strings) may differ. Capture the terminal narration and the Setup
check output.

---

## Build / run / test commands

```bash
# Build + run the native app (compiles native/*.swift as one module; sets CC/PATH to avoid the
# `cc` == copilot-CLI collision that shadows the C compiler):
scripts/control-tower-tray.command
CT_OPEN_ADMIN=1 scripts/control-tower-tray.command   # jump straight to Admin mode

# Offline engine test suite (mock gh, refuses to run if gh is not the mock):
bash scripts/tests/test_admin_bootstrap.sh           # expect: 137 passed, 0 failed

# Verify against real GitHub (read-only), by hand:
scripts/admin_bootstrap.sh --verify --brief "<brief path>" --json | jq
```

Never invoke a bare `copilot` (collides with `gh copilot`; installed here as `cc`).

---

## Key files

| Area | Path | Lines |
|---|---|---|
| Engine | `scripts/admin_bootstrap.sh` | 1531 |
| Skill | `.claude/skills/admin-bootstrap/SKILL.md` | 193 |
| Tests + mock gh | `scripts/tests/test_admin_bootstrap.sh` (+ `fixtures/bin/gh`) | 1252 |
| App | `native/admin.swift` + `native/admin-support.swift` | 2008 + 751 |
| Contract | `docs/01-architecture/admin-standup-contract.md` | 524 |
| Service design | `docs/03-design/admin-experience-service-design.md` | 395 |
| Interaction design | `docs/03-design/admin-experience-interaction-design.md` | 981 |
| Walkthrough (mockups) | `docs/09-prototypes/admin-experience-walkthrough.html` | 1667 |
| Admin prerequisites doc | `docs/06-deployment/admin-prerequisites.md` | 46 |
| Copy deck (Surface 3) | `docs/03-design/control-tower-copy-deck.md` | — |

Published walkthrough artifact: https://claude.ai/code/artifact/00a0a7a2-3367-483d-ba2d-05ca10c8d0c1

---

## Ratified decisions (do not reopen)

- **Repo naming:** component-first, no company suffix. Org: `<org>/claude-copilot` or
  `<org>/codex-copilot` (by harness), `knowledge-copilot`, `cli-copilot`; departments append
  `-<unit>`. Full component × layer matrix (3 repos at org + 3 per department).
- **Harness:** org-wide choice at standup (Claude Code shop or Codex shop). Individuals may add the
  other personally; an org can add the second later as a safe additive re-run.
- **Setup execution:** Claude Code leads via the OSS skill + deterministic engine; the app teaches,
  collects, and verifies, and **never fires GitHub mutations**.
- **Integrations:** the admin **never declares** them. They are built at the repo level by a
  department engineer and published via an in-repo registry manifest; the admin experience is
  education-only. `ecosystem.yml` carries components, departments, harness, store pointer only.
- **Secret store:** educate + connect-or-defer (not a hard gate).
- **Policy signing:** deferred entirely from v1 (GitHub branch protection instead).
- **User management:** GitHub only. No members panel; "Someone left" is instructional.
- **Org name is an existing identifier** (used verbatim, GitHub org-name rules, uppercase allowed);
  only departments are slugs we derive (lowercase).

Rationale and the full decision record: project memory `admin-redesign-decisions` and the design docs
above.

---

## Follow-ups (not done)

- **The live test itself** (the top priority — nothing has touched real GitHub).
- The 4 stubbed seams above, when their contracts exist (org-ownership check, Someone-left lookup,
  Org-setup live fetch, Publisher handoff schema).
- **WS-A:** the interim bash engine migrates into a signed `copilot admin bootstrap --json` CLI verb
  at freeze; these verbs/schemas already carry `schema_version`.
- Packaging: the native app is an **unsigned local prototype** (run via the launcher), not notarized
  or distributed.
- **The actual value is separate, unbuilt work:** a successful standup creates *empty* scaffolding.
  The agents, skills, knowledge, and integrations that make the ecosystem useful are authored into
  those repos afterward, per department. That is the next real body of work.
- Restore `allScreensUnlockedForReview = false` if that review flag is still set anywhere before real
  use (check `native/`).

---

## Conventions (do not regress)

- **No em-dashes** in user-facing copy (periods, commas, colons, parentheses only). **No time
  estimates. No aggregate scores.** Calm air-traffic-controller voice.
- **Never run `Process`/blocking I/O** in a SwiftUI model `init()` or first layout (prior
  AttributeGraph crash); defer to `.task {}`/background queue, deliver on `@MainActor`.
- **Parse-never-compute:** no `gh`/GitHub mutation logic in Swift, ever.
- **Concurrent sessions:** this repo tree is worked by multiple Claude/Codex sessions at once. Check
  `git log`/`git status` for a sibling's commits before staging, committing, or pushing (see the two
  unpushed non-admin commits noted above).
