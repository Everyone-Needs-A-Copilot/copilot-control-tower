# Admin Agentic Org-Setup

| | |
|---|---|
| **Status** | Proposed (architecture). Extends the ratified Admin-mode design (`control-tower-interaction-spec.md` §5) with the automation engine that section assumed but did not specify. |
| **Owner** | Architecture pass |
| **Reads on** | `docs/10-reference/four-tier-topology.md` (repo/team naming — authoritative), `docs/05-security/credentials-and-boundary.md` (shared store, secrets-never-in-git), `docs/10-reference/cse-alignment-decisions.md` (D1–D10), `docs/03-design/three-role-journeys.md` §2 (Admin journey), `docs/03-design/control-tower-interaction-spec.md` §5 (Admin mode), `docs/01-architecture/cli-contract.md`, `CLAUDE.md` invariants #1/#3/#4/#6. |
| **Closes gaps** | G6 (seed generator, engine half), G7 (setup verification), **G8 (GitHub topology is docs-only, not an in-app flow)** — this is the primary gap this spec closes. |
| **Governing invariants** | #1 parse-never-compute · #3 never-destroy (additive/idempotent) · #4 security inherited-not-weakened · #6 one-way inheritance, secrets never in git. |

---

## 0. What this adds and why

The three-role Admin journey (`three-role-journeys.md` §2b) lists A1 "Stand up repos" and
A2 "Grant team access" as **Design (docs only)** — the admin reads the topology doc and does
the GitHub work by hand. G8 names this as a gap. The interaction spec §5 designs the *GUI*
(seed generator, team-grant surface, preflight) but leaves the **engine** — the thing that
actually creates the repos, teams, grants, and seed — unspecified.

This spec designs that engine: an **agentic bootstrap capability** that automates the GitHub
standup, plus the app-side seam that triggers and renders it. It upgrades A1/A2 from
*teach-and-verify* to *trigger-and-render*, while keeping the two steps that categorically
cannot be automated (creating the GitHub org; granting `admin:org` scope) as guided TEACH
(`three-role-journeys.md` §0: "must be guided ≠ must be automated").

**Vocabulary is pinned by D2:** *component* = a CSE tool (`knowledge`/`cli`/`claude`/`codex`);
*layer/tier* = foundation → org → department → personal; *entitlement* = GitHub repo access.
The bootstrap stands up **components × shared tiers**, never products/projects (D10).

---

## 1. The agentic bootstrap capability

### 1.1 Shape: skill (face) + CLI verb (engine) — the same split the app uses

The recommended split mirrors the app↔CLI relationship one level up. **The skill is to the
CLI what the app is to the CLI:** a face that collects inputs and narrates/renders, delegating
every computed, security-load-bearing, or never-destroy-governed operation to a versioned CLI
verb. This is invariant #1 applied to the agentic surface: *the LLM must never be the thing
that decides whether a repo already exists before creating it* — that is a fail-closed
idempotency check that must be deterministic code, not a prompt.

| Layer | Home | Owns |
|---|---|---|
| **Face (agentic)** | An open-source **skill/command** shipped in *this* repo (`/.claude/skills/admin-bootstrap/`, Claude-Code- and Codex-runnable, fully inspectable) | Conversationally gather org/dept/integration/member inputs; check prerequisites (`gh auth`, scopes); **invoke the engine**; narrate per-step JSON results in plain language. Holds **no** trust-critical logic. |
| **Engine (deterministic)** | A **`copilot admin bootstrap --json`** CLI verb (lives beside `admin/seed.rs`, versioned, signed, contract-tested) | The ordered, idempotent, additive GitHub orchestration (§1.3); naming-convention enforcement; never-destroy existence checks; seed authorship/merge; fail-closed leak-scan; per-step result emission. |
| **App (GUI)** | Control Tower Admin mode (§3) | Collect the same inputs via forms; shell to the **same** verb; render the **same** JSON. No `gh`/GitHub logic in Swift. |

Three faces (skill, GUI, headless CLI), **one engine**. If Control Tower vanished, the skill
still stands up the org; if the LLM refuses, the CLI verb still runs headless. The guarantees
(idempotency, never-destroy, leak-scan) are contract-testable independent of any LLM, exactly
as the app↔CLI contract test asserts today (`cli-contract.md` §"Contract test").

### 1.2 Interim reality (WS-A is unstarted)

`copilot admin bootstrap` does **not** exist yet — WS-A is unstarted and the CLI contract is
frozen-on-paper only (`cli-contract.md` freeze banner). So the capability ships in two phases,
and the split makes the migration clean:

- **Phase now (pre-WS-A):** the skill drives a **vetted, idempotent, inspectable `gh` script**
  shipped in the repo (`scripts/admin_bootstrap.sh`) as the engine. The script — not the LLM —
  carries the check-then-act guards, the naming enforcement, and the leak-scan. Its behavior is
  covered by a script-level test (existence-check, re-run-is-noop, refuse-on-missing-scope), so
  the never-destroy guarantee holds without trusting the model.
- **Phase at freeze:** the script's logic migrates **into** `copilot admin bootstrap --json`
  (a control-tower-originated WS-A addition, same status as `publish`/`layers` in
  `cli-contract.md`). The skill and the app both become thin callers of the verb; the script is
  retired. No guarantee changes hands — it was always in code, only its home moves.

> Guardrail note: this does **not** violate CLAUDE.md's "do not code the app before WS-A." The
> bootstrap capability is admin-facing open-source *tooling* (skill + script), not the
> supervised Tauri app. The app-side seam (§3) is design-only until the verb exists.

### 1.3 The GitHub automation sequence (ordered, idempotent, additive)

Enforces exactly the `four-tier-topology.md` conventions: `copilot-org` + `copilot-dept-<unit>`
separate repos (Option A default, §6.2), org **base permission = read** as the org-wide grant,
department read/write as a **narrower team grant on a separate repo** (never team nesting,
§6.3), foundation referenced **by version over anon HTTPS**.

**Inputs:** GitHub org name; department list; per-layer integrations (§2); optional team-member
usernames. All collected by the face (skill or GUI); the engine receives them as flags/stdin.

**Auth model (distinct from the consumption path).** The bootstrap is an **org-owner
administration** operation and uses the admin's own **`gh`** credential (HTTPS + token) with
elevated scopes. This is *not* the per-user SSH-alias path (`github-work`/`github-personal`)
that `four-tier-topology.md` §6.1 defines for *clone/materialize* and *author push* — those are
consumption credentials. Creation needs org-admin API scope; consumption needs a read (or
per-author write) key. The bootstrap never provisions or touches a personal-tier credential.

| # | Step | Mechanism | Idempotency / never-destroy |
|---|---|---|---|
| 0 | **Preflight auth + scope** | `gh auth status`; verify actor is an **owner** of `<org>`; require scopes `repo` + `admin:org` | **Refuses** (exit 2, plain instruction) if unauthenticated, not an owner, or scope missing. Teaches `gh auth refresh -s admin:org -s repo`. No mutation before this passes. |
| 1 | **Org base permission = read** | `gh api -X PATCH /orgs/{org} -f default_repository_permission=read` | Setting to the same value is a native no-op. This is the org-wide read grant (every member reads `copilot-org`), §6.3. |
| 2 | **Create `copilot-org`** (private) | GET-then-POST: check repo exists; if absent, create; seed foundation wiring (`ecosystem.yml`/`copilot.layers.yml` referencing `Everyone-Needs-A-Copilot/claude-copilot` by version `^5.x`, anon HTTPS) | If it **exists with content**, NEVER overwrite: report `already-present`, verify shape, continue (#3). Seeding an *empty* repo is additive (initial commit, never force). |
| 3 | **Per department** (loop) — repo | GET-then-POST `copilot-dept-<unit>` (private); `<unit>` slugified per convention | Existing repo → `already-present`, never clobbered. |
| 3a | — team | GET-then-POST team `<org>/<unit>` (`gh api /orgs/{org}/teams`) | Existing team → `already-present`. **Not** nested under an org-parent team (nesting cascades parent→child and would leak every dept to every member, §6.3). |
| 3b | — grant (entitlement) | `gh api -X PUT /orgs/{org}/teams/{unit}/repos/{org}/copilot-dept-<unit> -f permission=push`(authors) / `pull`(members) | PUT is natively idempotent. **This grant *is* the entitlement** (D3). |
| 3c | — members (if provided) | `gh api -X PUT /orgs/{org}/teams/{unit}/memberships/{user}` | PUT is idempotent; re-adding a member is a no-op. |
| 4 | **Write/update the seed** (`ecosystem.yml`) | Additive merge: components, foundation pins, departments (`topology: separate` default), `policy_signers`, and per-layer **integration definitions + `requires_secret` references + store endpoint reference** (§2) | Re-run **adds** a new dept/integration entry; **never rewrites** existing entries. Committed via PR into `copilot-org` (or initial commit on the empty repo), never direct-push to protected content — one-way, additive (#6). |
| 5 | **Fail-closed leak-scan** | Run the existing leak-scan (`four-tier-topology.md` §8.2 deny-list) over the seed **before any push** | Seed carries only `requires_secret: <NAME>` refs + the store **endpoint URL** (not a secret, D4/D6). A value that looks like a secret → **refuse to push** (#6, and the §5.5 secret-shape refusal). |
| 6 | **Verify** | Hand off to setup verification (§4) | Read-only; computes nothing destructive. |

**Departments-as-you-go.** `copilot admin bootstrap --add-department <unit> --json` (skill:
"add a department") runs only steps 3–5 for that one unit + 6. Re-running for an existing
department is a **full no-op**: repo exists → skip; team exists → skip; grant exists → skip
(idempotent PUT); seed already carries the entry → skip. Never duplicates, never destroys (#3).

**Idempotency mechanism, stated once.** Every mutation is **check-then-act** (GET before
POST/PATCH). GitHub's team-repo-permission and team-membership PUTs are natively idempotent;
`PATCH default_repository_permission` is a set-to-value no-op. The only non-idempotent
primitives are repo/team *creation* (POST 422 on duplicate), each guarded by an explicit
existence GET. Every step emits `{step, result: created|already-present|skipped|refused|failed,
detail}` so the face renders exactly what happened — **no aggregate, no score.**

### 1.4 Safety — what it requires, refuses, and never clobbers

- **Requires org-owner rights** (`admin:org`): team creation, base-permission, and membership
  all need it. Without it the engine **refuses** at step 0 with a plain instruction — it never
  half-creates.
- **Never creates the GitHub org itself** — org creation needs billing + a human at
  github.com. The engine *verifies* the org exists and the actor is an owner; if not, the face
  **teaches** (the categorical-automation boundary, `three-role-journeys.md` §0).
- **Never clobbers an existing repo with content** — GET-then-act; an existing repo is reported
  `already-present` and left as-is (#3). It never overwrites, force-pushes, deletes, or passes
  `--force`/`--skip-verify` (#4).
- **Never touches the personal tier** — personal is the user's own account under their own
  key; the org bootstrap has no write path to it (one-way inheritance, #6).
- **Secrets never committed** — the seed carries only references + the (non-secret) store
  endpoint; the fail-closed leak-scan (step 5) is the defense-in-depth backstop, the structural
  guarantee is that no field in the form accepts a secret shape (§5.5 refusal, reused).

---

## 2. Integration management per layer

**The model that fixes "don't show Workday if I don't have it."** The seed gains a per-layer
`integrations` block. Each entry declares an integration that **exists** at that layer and
points at the shared store (endpoint + scope), **never the key** (D6, credentials §1.6):

```yaml
# ecosystem.yml (excerpt) — authored by the seed generator, never hand-edited
integrations:
  org:
    - id: salesforce
      requires_secret: SALESFORCE_API_KEY   # a NAME, never a value
      store_scope: org                       # resolves against inherited shared_secret_store_url
    - id: microsoft365
      requires_secret: MS365_TOKEN
      store_scope: org
    # Workday is ABSENT → it exists nowhere → no entitled user ever sees it
  department:
    sales:
      - id: hubspot
        requires_secret: HUBSPOT_KEY
        store_scope: dept/sales
```

- **Declaring which integrations exist** is an admin act in the seed generator (§5.4 gains a
  per-layer integration list). Declaring Salesforce + Microsoft 365 but **not** Workday at org
  is the whole mechanism: **absence = non-existence.** No user, at any tier, can see an
  integration that no layer declares.
- **The seed never carries the secret.** Each entry is `requires_secret: <NAME>` (a reference)
  + a `store_scope` that resolves against the inherited `shared_secret_store_url` (delivered via
  inherited org config, D4/D6). The endpoint URL is not a secret; access is gated at the store.
- **Two gates, both GitHub-team membership** (D3 applied to integrations):
  1. **Visibility gate** — the integration must be declared in a layer the user is **entitled**
     to (has team-read on that layer's repo). A user in Sales sees org integrations
     (Salesforce, M365) + Sales dept integrations, and never another department's.
  2. **Access gate** — the shared store hands the secret only to **members of that tier's team**
     (credentials §1.6.2 step 3). A non-member who somehow learns the endpoint gets a **403**,
     not the key.
- **Entitlement makes a user SEE only their integrations.** `copilot integrations --json`
  (the Stage-1 open-decision-4 verb the app renders in the Shared register, interaction-spec
  §2.6/§4.4) computes, per user, the union of integration entries across the layers they have
  **joined** — CLI-computed, app-rendered (invariant #1). Workday is invisible because it is in
  no layer the user is entitled to; even if it were, the store would refuse the secret. This is
  the "shared, entitled, read-only, no sign-in" register (D7.2) — the opposite of personal
  device-flow sign-in.

---

## 3. The Admin-mode seam (parse-never-compute)

The app **collects** and **renders**; the capability **computes** and **executes**. No
GitHub-creation logic ever lives in Swift.

| | Handled by |
|---|---|
| **App COLLECTS** | Org name; department list (add-over-time); per-layer integrations (`id` + `requires_secret` name + `store_scope`); member usernames per team; the GitHub connection (the app does **not** hold the token — it triggers the capability, which uses the admin's own `gh`/on-device credential). Via the §5.4 seed generator + §5.6 team-grant forms — constrained inputs, secret-shape refusal (§5.5). |
| **App RENDERS** | The capability's streamed per-step JSON: per-repo/per-team/per-grant status (`created`/`already-present`/`refused`), the seed-commit PR ref, then the setup-verification red/green (§4) with per-item owner. Named-phase progress, **no ETA, no aggregate score**. |
| **Capability COMPUTES/EXECUTES** | Everything in §1.3: existence checks, repo/team/grant creation, base-permission, seed authorship + leak-scan, verification. The app shells to `copilot admin bootstrap --json` / `--add-department` and renders; it **never** calls `gh` or the GitHub API itself. |

**What changes in the existing Admin flow.** The Onboarding checklist item **"GitHub topology"**
(interaction-spec §5.2 sidebar) flips from a *teach-and-verify page* to a **trigger-and-render**
page: it collects org + departments, confirms scopes (TEACH if `admin:org` is missing), fires
the capability, renders per-repo/per-team progress, and hands to Preflight. The **seed generator
(§5.4)** now feeds its assembled seed to the same engine (which validates + drives the
bootstrap). The **team-grant surface (§5.6)** — which already effects grants via the author's own
credential — is the per-department slice the bootstrap automates in bulk. This closes G8 and the
engine half of G6.

**New CLI contract surface** (control-tower-originated proposals, not yet upstream WS-A scope,
same status as `publish`/`layers` — fold in at freeze):
`copilot admin bootstrap --json`, `copilot admin bootstrap --add-department <unit> --json`, and
`copilot admin bootstrap --verify --json` (or reuse `copilot admin preflight --json`, §4). All
carry `schema_version`; `leak_scan` and any secret-adjacent field are **fail-closed** (missing ⇒
refuse), matching the contract's global rule.

**The skill runs outside the `admin_capable` gate.** The GUI Admin mode is gated by
`admin_capable` (interaction-spec §5.1). The **skill runs in Claude Code/Codex, entirely outside
the app** — it is the alternative path for an admin who never opens the GUI, and it is not gated
by that boolean. The gate governs the *GUI surface*, not the *capability*.

---

## 4. Setup verification (red/green, owner-named, no aggregate)

Reuses the existing `PreflightReport` grammar (interaction-spec §5.7): one row per check,
`status ∈ pass|fail|unknown`, **unknown is never green**, **no aggregate score ever**, the
honest summary is a **count** ("2 must be fixed, 1 could not be checked"), and **every fail/unknown
names its owner**. CLI-computed (`copilot admin bootstrap --verify` / `copilot admin preflight`),
app-rendered. The bootstrap contributes these check rows:

| Check | Passes when | Owner named on fail/unknown |
|---|---|---|
| Org repo + base-read | `copilot-org` exists **and** `default_repository_permission = read` | Admin (repo) / GitHub org owner (base-perm) |
| Department repos | each `copilot-dept-<unit>` exists | Admin |
| Team grants entitlement | each dept team exists **and** grants read/write on its repo | Admin |
| Members provisioned | provided usernames are team members | Admin |
| Seed valid + signed | `ecosystem.yml` parses, is signed by an allowed `policy_signer`, foundation pin resolves | Admin / Policy signer |
| Shared store reachable | the inherited `shared_secret_store_url` responds and tier scopes map to teams | IT infra |
| Foundation reference | the version-pinned anon-HTTPS foundation resolves | Auto / ENAC (external) |

Each red drills into the plain `detail` + a fix affordance appropriate to the owner
(Admin-owned → jump to the offending onboarding step; others → plain instruction + handoff ref).
Never a raw GitHub/git/serde string. This closes G7.

---

## 5. Open decisions for the owner

1. **Interim engine home** — ship the vetted idempotent `gh` script (`scripts/admin_bootstrap.sh`)
   as the engine **now** (pre-WS-A), migrating into `copilot admin bootstrap` at freeze
   (recommended: the script's guarantees are contract-testable independent of the LLM), **or**
   wait for the upstream verb before shipping any automation?
2. **WS-A scope** — fold `admin bootstrap [--add-department] [--verify] --json` into upstream
   WS-A scope alongside `publish`/`layers` (currently control-tower-originated, not upstream).
3. **`admin:org` acquisition** — teach `gh auth refresh -s admin:org` on the admin's own PAT,
   **or** stand up a **GitHub App** with fine-grained org-admin permissions (avoids a broad user
   PAT; adds custody of an App private key — which the shared store is the right home for, per
   credentials §6.4)? Recommend flagging; App is cleaner but heavier for a first cut.
4. **Fresh-repo seed delivery** — a PR into `copilot-org` needs a pre-existing branch/CODEOWNERS
   (chicken-and-egg on an empty repo). Recommend: **initial commit on the empty repo, enable
   protection after** (additive/never-destroy since the repo is empty); switch to PR-only once the
   repo carries content.
5. **Integration classification** — which integrations the seed may declare as shared-store-backed
   vs. must-stay-personal (credentials §1.6.5 leaves the per-integration list open). Needed before
   admins classify their own (Salesforce/M365 shareable; anything acting as an individual identity
   must stay per-user).
6. **`admin_capable` path 2a vs 2b** (already open, interaction-spec §5.1) — unaffected here, but
   note the skill is a third, un-gated path for admins who never open the GUI.

---

## 6. Invariant conformance

| Invariant | How this design holds it |
|---|---|
| **#1 parse-never-compute** | The app collects + renders; the *skill* narrates; the *engine* (CLI verb/script) computes and executes. No GitHub logic in Swift; the LLM never makes the fail-closed idempotency decision. |
| **#3 never-destroy** | Every mutation is check-then-act; existing repos/teams/grants are `already-present`, never clobbered; re-run and add-department are no-ops; no force/delete/overwrite. |
| **#4 security inherited, not weakened** | No `--force`/`--skip-verify`; store endpoint honored only from inherited org config; trust roots (foundation version, policy signers) not user-editable; org-owner scope required and refused-without. |
| **#6 one-way inheritance, secrets never in git** | Seed carries only `requires_secret` refs + the non-secret store endpoint; fail-closed leak-scan before any push; the bootstrap has no write path to the personal tier; publishing is additive PR/initial-commit, never a cross-tier sync. |
