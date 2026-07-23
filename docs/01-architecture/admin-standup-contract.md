# The Admin standup contract (machine contracts for the redesigned Admin experience)

> **Implementation amendment — 2026-07-23.** The packaged Admin app now owns
> the complete zero-terminal transaction. It automatically checks its bundled
> tools, GitHub identity, required scopes, and active organization-owner role;
> browser-authorizes GitHub when needed; renders the engine's read-only
> repository plan; invokes apply only after **Set up organization**; and renders
> verify from a fresh read. This supersedes the historical baton-pass language
> in §0, §1's “app → terminal” framing, §2, and the skill-materialization
> requirements. The deterministic engine, brief schema, fail-closed plan/apply
> behavior, idempotence, ownership boundary, and verify schema remain
> normative. The Markdown brief remains human-readable; the app passes its
> JSON twin to the engine so Python is not a packaged runtime dependency.

| | |
|---|---|
| **Status** | Implemented with the 2026-07-23 zero-terminal amendment above. Historical baton-pass sections remain for lineage and are non-normative where the amendment supersedes them. |
| **Serves** | `docs/03-design/admin-experience-service-design.md` (the approved service blueprint, Journeys A/B/C) and `docs/03-design/admin-experience-interaction-design.md` (the 16-surface interaction spec). Everything here must render exactly what those two design docs describe. |
| **Reads on (authoritative)** | `docs/10-reference/four-tier-topology.md` (resolver / teams / auth mechanics), `docs/01-architecture/cli-contract.md` + `schemas/_envelope.schema.json` (schema_version, fail-closed conventions), `docs/10-reference/copilot-solutioning-ecosystem.md` (CSE component model). |
| **Supersedes (in part)** | `docs/03-design/admin-agentic-setup.md` and `docs/03-design/control-tower-admin-flow.md` — see the reconciliation table (§7). |
| **Governing invariants** | #1 parse-never-compute (the app collects, confirms, invokes, and renders; a deterministic engine computes and executes) · #3 never-destroy (additive/idempotent) · #4 security inherited-not-weakened (no `--force`/`--skip-verify`, no bypass; **no signing/policy-signer machinery anywhere in v1**) · #6 one-way inheritance, secrets never in git (no field defined here may hold a secret). |

---

## 0. The division of labor this contract freezes

Three actors, three faces, one engine. This contract defines the seams between them precisely
enough that the app, the skill, and the script can be built against it independently.

| Actor | Owns | Never does |
|---|---|---|
| **The app** (Control Tower, Admin mode) | Collects the org description into a non-secret **brief** (§1); renders the **verify verb** (§3) and the read-only **registry** roll-up (§5). | Fires no GitHub mutation; computes no verdict; holds no token. |
| **Claude Code + the `admin-bootstrap` skill** | Reads the brief as opening context, re-confirms with Earl, drives the **engine script** (§6), narrates each `{step,result,detail}` in plain language. | Makes no check-then-act decision itself — the script does (invariant #1 one level up). |
| **The engine** (a deterministic idempotent `gh` script now; `copilot admin bootstrap` at freeze) | The ordered additive GitHub matrix (§6), naming enforcement, branch protection, `ecosystem.yml` authorship, fail-closed leak-scan, and the `--verify` read (§3). | Never touches a dirty tree, never `--force`, never provisions people, never writes an integration. |

### 0.1 Shared setup and personal handoff

Admin Setup owns the overall readiness outcome, but its write authority ends at
the shared organization boundary. It creates or verifies foundation references
and organization repositories, then emits a non-secret handoff that User Setup
consumes after the individual authenticates with their own GitHub identity.

User Setup creates or selects the individual's personal repositories and installs
rank-10 content. Admin Setup may render only the opaque result returned by `cc`
(present/missing, resolved rank, source provenance, and health); it never creates,
owns, clones, inspects, or writes a personal repository. This boundary applies to
both Claude and Codex and is ratified in
[`ADR-004`](../40-initiatives/02-enac-self-onboarding/decisions/ADR-004-admin-shared-user-personal-onboarding.md).

**Every artifact and verb defined here carries `schema_version` from day one** (§8), following the
`_envelope.schema.json` convention: `MAJOR.MINOR[.PATCH]`, range-gated in both directions,
security-adjacent fields fail-closed (a missing/unreadable security field is never treated as safe).

---

## 1. The standup brief

The single artifact that crosses the app -> terminal boundary. It is a **starting point, not a
contract**: the skill re-confirms with Earl and may diverge; GitHub truth wins, and the verify
verb (§3) reveals drift.

### 1.1 On-disk location

**DECISION:** the brief lives at a fixed, app-owned path:
`~/Library/Application Support/CopilotControlTower/standup-brief.md`.
Rationale: Control Tower is a Developer-ID-signed, notarized, **non-sandboxed** menu-bar
supervisor (it shells the `copilot` CLI and re-materializes `.claude/` trees; the App Store
sandbox would forbid both), so `Application Support` resolves to a real, external-readable path
that the out-of-sandbox `claude` process can open. It is app-owned and stable across re-runs
(a single fixed filename, never timestamped, so the Setup check always reads the same baseline),
and it is **never inside any git working tree**, so it can never be committed. `Library` being
Finder-hidden is a non-issue: **Reveal in Finder** opens the containing folder directly (the
Review surface's `Reveal >` affordance, interaction-design Surface 8).

**DECISION:** exactly **one canonical brief**, rewritten in place on every write (standup and
every governance re-run). There is no per-run or "small re-run" file. Rationale: the brief must
persist as the verify verb's expected-set baseline for drift (§1.4); a second artifact would fork
the baseline. This supersedes the interaction-design Surface 14 "small re-run brief" framing:
the change is small, but the *artifact* is the same brief, rewritten to carry the full new
expected set. The engine's idempotency (§6), not a reduced brief, is what makes a re-run "only
add what's new."

### 1.2 Format

**DECISION:** YAML **front-matter** (a leading `---` fenced block) carries the machine-parseable
structured data; markdown **prose sections** below carry the human-reviewable narrative.
Rationale: front-matter sits at a fixed, unambiguous head position that both the app and the skill
key on the leading `---`, rather than hunting a fenced block inside prose; and the same file reads
cleanly for Earl. `schema_version: "1.0"`.

```markdown
---
schema_version: "1.0"
org: acme-co                       # GitHub org slug (validated as a slug at collection)
harness:                           # a LIST; the second-harness re-run appends, never replaces
  - codex
departments:                       # ordered list of dept slugs; full current expected set
  - accounting
  - sales
store:                             # connected -> pointer; deferred -> explicit marker
  status: connected                # connected | deferred
  type: infisical                  # store type (picker value); omitted when deferred
  endpoint: https://vault.acme-co.com   # a URL, NOT a secret
  workspace_id: "workspace-acme"   # project/workspace identifier, NOT a secret
  environment: prod                # exact environment slug for device read access
  secret_path: "/shared"           # exact path for device read access
  team_scopes:                     # which team maps to which store scope
    - { team: accounting, scope: dept/accounting }
    - { team: sales,      scope: dept/sales }
github_app:                        # the company's OWN GitHub OAuth App (device-flow sign-in)
  client_id: Iv1.a1b2c3d4e5f6a7b8  # PUBLIC identifier, NOT a secret; the client secret is never used
contacts:                          # metadata for the handoff header + verify owners; not user mgmt
  publisher: "Dana R."
  admin: "Earl P."
  point_of_contact: "it@acme-co"
---

# Standup brief for acme-co

## What this describes
acme-co, a Codex shop, with departments Accounting and Sales. Its shared secret
store is connected. This file carries no secrets and no integrations.

## Departments
- Accounting
- Sales

## Shared secret store
Connected: Infisical at https://vault.acme-co.com. Accounting -> dept/accounting,
Sales -> dept/sales.

## Company GitHub app
acme-co created its own GitHub OAuth App, "Copilot Control Tower", with device flow
enabled. Its Client ID is public config that travels in the org setup file, so every
person's "Connect GitHub" sign-in runs through acme-co's own app. The app's client
secret is never collected and never used.

## What this file is
A plain description Claude Code reads as a starting point. It confirms it with you,
then does the work. GitHub is the source of truth; the Setup check reads it fresh.
```

The **deferred** store renders as `store: { status: deferred }` in front-matter and an honest
"connect a store before your first shared integration" line in prose. No `endpoint`, no
`team_scopes`.

### 1.3 Field inventory (authoritative)

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string `MAJOR.MINOR[.PATCH]` | `"1.0"`. Range-gated; a brief outside the app's floor/ceiling is refused, not guessed. |
| `org` | string (GitHub organization login, verbatim) | The **existing** GitHub org's real login, case-preserving: GitHub's own org/username rule (ASCII letters of either case, digits, single hyphens, never leading/trailing/doubled, 1-39 chars) is validated at collection, but the value itself is never transformed (never lowercased, never slugified) — it names something that already exists on GitHub, unlike `departments` below. |
| `harness` | list of `claude` \| `codex` | Org-wide harness choice(s). One entry at standup; the second-harness re-run appends the other. Drives every repo name. |
| `departments` | list of slugs | The **full current** expected set (a re-run rewrites the whole list). Unlike `org`, these are slugs the engine itself **generates** repo names from, so they are forced lowercase (`_valid_slug`), distinct from `org`'s case-preserving `_valid_org` rule. **`internal` is reserved** for the org layer (`<C>-copilot-internal`) and is refused as a department name. |
| `store.status` | `connected` \| `deferred` | Deferred is a first-class, honest value, never an omission. |
| `store.type` / `store.endpoint` | string / URL | Present only when connected. Endpoint is not a secret (access stays gated at the store by GitHub-team membership). |
| `store.workspace_id` / `store.environment` / `store.secret_path` | strings | Required for connected Infisical. Non-secret scope identifiers used by User Setup to provision exact-path, read-only device access. |
| `store.team_scopes[]` | `{team, scope}` | Non-secret mapping; present only when connected. |
| `github_app.client_id` | string (GitHub OAuth App client id) | The company's **own** OAuth App identifier, created during standup (§1.6). **Public, not a secret** (it rides in every device-flow request); the client secret is never collected or used. Written into `ecosystem.yml` (§4) so user installs read it for the "Connect GitHub" device flow. Collection accepts GitHub's stable 20-character public identifier shape (ASCII letters, digits, or dots), including legacy `Iv1.` and current prefixes. |
| `contacts.{publisher,admin,point_of_contact}` | string | Labels for the handoff header and verify-verb owner names. Never grant or change access. |

No `integrations` block (the admin declares none; existence lives in per-repo registries, §5).
No `policy_signers` (deferred from v1; the script configures branch protection instead, §6).
No version pins (Earl chooses no versions in v1; the script applies the foundation pin, §4/§6).

### 1.4 Lifecycle

1. **Standup write.** At Review and hand off (Surface 8) the app writes the brief from the
   collected inputs, after every field has passed the secret-shape refusal (§1.5). If the write
   fails (disk/permissions), the app withholds the copyable command and offers retry — it never
   hands off a command pointing at a missing brief.
2. **Persist as drift baseline.** The brief stays on disk. The verify verb (§3) compares its
   declared expected set (org, harness list, departments, store pointer) against GitHub truth.
3. **Governance re-run rewrite (in place).** A governance action rewrites the *same* brief to the
   new full expected set:
   - **Add a department:** `departments` gains the new slug (e.g. `+ it`); everything else
     unchanged. The verify baseline grows to expect the new triplet + team.
   - **Add the second harness:** `harness` gains the other value (`[codex]` -> `[codex, claude]`).
     The baseline grows to expect the second harness's triplets.
   - **Connect the store later:** `store` flips `deferred` -> `connected` and gains `endpoint` +
     `team_scopes`. The baseline gains the store row.
4. **Skip-the-brief path.** If Earl describes the org to Claude Code from scratch, the skill
   gathers everything conversationally; the brief is a head start, not a gate (§2 precedence).

### 1.5 Secret invariant

**No field defined here may hold a secret.** The guarantee is structural: the secret-shape
refusal fires **at collection** (the app rejects a secret-shaped value inline and never stores it,
on the two surfaces that still collect a store endpoint), so the brief is secret-free by
construction. The engine's fail-closed leak-scan (§6 step 6) is the defense-in-depth backstop over
`ecosystem.yml` before any push, not the primary guarantee.

### 1.6 The company's GitHub OAuth App (device-flow sign-in)

**DECISION (owner-ratified, 2026-07-16):** every company creates **its own** GitHub OAuth
App during standup. The foundation never provides one, and no company uses another company's
client id. The app's **Client ID is public** (it appears in every device-flow request), so it
travels in the org's inherited `ecosystem.yml` (§4) and each person's "Connect GitHub"
device-flow sign-in runs through the company's own app. Rationale: GitHub's device flow is the
only secret-free native path (integration-auth-research §3.1), and org OAuth-app access
restrictions are on by default for new orgs, so a per-company app is the honest, self-contained
shape. A client id is not a secret and may travel in inheritance; the client secret never is and
never travels (invariant #6).

**The admin step (a documented standup surface, near Connect GitHub).** Plain instructions the
app teaches; the admin does the GitHub-web action, the app collects the result:

1. Go to github.com, open the company org, then **Settings -> Developer settings -> OAuth Apps
   -> New OAuth App**.
2. Name it clearly, for example **Copilot Control Tower**. The homepage and callback URLs can be
   the company's own site; device flow does not use the callback.
3. **Enable Device Flow** on the app.
4. **Leave the client secret unused.** The product never needs it and never asks for it.
5. Copy the app's **Client ID** and paste it into the standup field. The app validates GitHub's
   20-character public identifier shape and records it in the brief as `github_app.client_id`.

**Where it goes.** The brief carries `github_app.client_id` (§1.3); the engine writes it into the
org's `ecosystem.yml` (§4). No secret is collected at any point: the collection field takes only
the public client id, and the secret-shape refusal (§1.5) still guards it.

**Verify behavior.** The verify verb (§3) emits a `github-app` row and asserts that
`ecosystem.yml` carries the same present, well-formed `github_app.client_id` as the brief. A
missing, malformed, or different identifier is a fixable Admin-owned failure rather than a silent
failure at every user's first sign-in.

---

## 2. The handoff command

The single copyable line the Review surface (Surface 8) presents. Because the app orchestrates
nothing in the terminal, this is a clipboard convenience plus an **Open Terminal** helper.

**Contract (what the line must convey):** start an **interactive** Claude Code session with the
`admin-bootstrap` skill invoked as the opening prompt, with the brief at its fixed path (§1.1).

**DECISION (verified against `claude --help` on this machine):** there is **no `--skill` flag**;
skills resolve via **slash-command syntax inside the prompt argument** ("Skills still resolve via
/skill-name"). Canonical rendered shape:

```
claude "/admin-bootstrap ~/Library/Application Support/CopilotControlTower/standup-brief.md"
```

- This starts an **interactive** session with the skill invoked as the opening prompt, which is
  exactly the conversational baton pass the design wants. **Do NOT use `-p`/`--print`** — the
  session must stay interactive so Claude Code can converse, absorb mess (gh missing, org not
  created yet, wrong scopes, a partial prior run), and narrate each `{step,result,detail}` (§6).
- The skill id (`admin-bootstrap`) and the brief path are the **load-bearing** parts; the app
  treats the quoted prompt as a single configurable template it can update to match the installed
  `claude` slash-command convention at build time without changing this contract.
- **Brief-absent precedence.** The brief path is also the skill's **default discovery location**,
  so the skill functions with or without the argument. Precedence: brief present -> the skill reads
  it as opening context and re-confirms; brief absent (skip-the-brief path, or first-ever run from
  the terminal) -> the skill **gathers conversationally** and writes no assumption.
- **Colliding-name hazard.** The pasted command is `claude` (Claude Code) and resolves on Earl's
  own `PATH` — it does not touch the `copilot`/`cc` CLI, so no collision arises at the handoff.
  But **any** `copilot`/`cc` shell-out the app or skill makes internally (notably the verify verb,
  §3) MUST use the **absolute, translocation-safe** binary path, never bare `copilot` (which
  collides with `gh copilot`, and the `cc` alias shadows the C compiler) — per CLAUDE.md Tech.

### 2.1 Skill delivery (the skill must exist before the command can resolve)

`/admin-bootstrap` resolves only from an installed skill (`~/.claude/skills/` user scope, or a
project's `.claude/skills/`). At Review-and-hand-off the admin has cloned nothing, so the skill is
not yet present and the command would silently fail to resolve the slash-command.

**DECISION:** Control Tower **ships the open-source `admin-bootstrap` skill inside its app bundle**
and **materializes it to `~/.claude/skills/admin-bootstrap/`** at the moment Review-and-hand-off
generates the command. Rationale: the skill is non-secret OSS content, so bundling it versions the
skill **with the app** (no network fetch, no clone step, no supply-chain surface at hand-off); the
write is an **idempotent overwrite-on-newer** (compare a bundled version marker; replace only when
the bundle is newer), which never touches user edits destructively beyond the app-owned skill dir
and is safe to re-run. It writes to user scope so it resolves from any terminal `cwd`. This is
app-owned OSS tooling, not the supervised app firing a mutation, so it stays inside invariant #1
(the skill and script, not the app, do the GitHub work). It touches no GitHub state, so the
**Setup check is unaffected** (materializing the skill is not a verify-verb concern).

- **Alternatives rejected:** (a) *clone-on-run inside the skill* — chicken-and-egg (the skill must
  exist to run) and adds a network dependency to the baton pass; (b) *a separate installer step* —
  a second thing to get right before the one copyable command works, defeating the one-line hand-off.
- **Fallback the command story requires.** Because a missing skill means `claude` simply won't
  resolve `/admin-bootstrap` (an opaque non-failure for Earl), **the Review surface offers the
  copyable command only after the skill is materialized.** If materialization fails (disk/
  permissions), the app withholds the command and offers retry, the same honesty as a failed brief
  write (§1.4) — it never hands off a command that cannot resolve. The skill is also downloadable
  from its OSS repo for the terminal-first admin who never opens the app (the skip-the-brief path).

---

## 3. The verify verb (`--verify --json`)

The read-only truth-after surface behind the Setup check (Surface 10). Freeze target:
`copilot admin bootstrap --verify --json`. Interim: the same engine script's `--verify` mode
emitting the **identical** JSON. The app **renders** these rows; it computes no verdict.

### 3.1 Envelope and row schema

```json
{
  "schema_version": "1.0",
  "checks": [
    {
      "check": "org-triplet",
      "status": "pass",
      "detail": "acme-co/codex-copilot-internal, knowledge-copilot-internal, cli-copilot-internal exist, private.",
      "owner": "Admin",
      "fix_surface": "describe"
    }
  ],
  "summary": { "must_fix": 1, "unknown": 0 }
}
```

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | `"1.0"`. Range-gated; out-of-range ⇒ the app refuses to render (never guesses). |
| `check` | string (stable id) | One of the inventory ids in §3.3. |
| `status` | enum | `pass` \| `fail` \| `unknown` \| `deferred` \| `present-undeclared` (§3.2). |
| `detail` | string (plain language) | Never a raw GitHub/git/serde string. |
| `owner` | enum | `Admin` \| `GitHub org owner` \| `IT infra` \| `ENAC/external`. Required on `fail`/`unknown`/`deferred`. |
| `fix_surface` | enum | `describe` \| `connect-github` \| `connect-store` \| `external` \| `none`. Where the app's "Go fix this" / "Connect" jumps. |
| `summary.must_fix` | integer | Count of `fail` rows only. Never a score/percentage. |
| `summary.unknown` | integer | Count of `unknown` rows only. |

**DECISION:** the status enum is the four the design names plus a fifth, `present-undeclared`, for
the drift-beyond-brief case (rationale: it must render distinctly from every other state — calm,
no owner, no fix, not counted — and folding it into `pass` would hide that GitHub did more than the
plan). `deferred` and `present-undeclared` are **excluded from both counts**.

### 3.2 Status semantics (drift, exactly as designed)

| Status | Meaning | Render | Counted? | Owner |
|---|---|---|---|---|
| `pass` | Brief-declared and verified true on GitHub. | green + `Ready`. | no | — |
| `fail` | **Brief-declared but missing/wrong** on GitHub. | red. | **must_fix** | named (usually **Admin**). |
| `unknown` | The check itself could not run. **Never green.** | distinct (orange). | **unknown** | named. |
| `deferred` | A valid deferred choice (store not connected). | neutral `not connected yet`, never red. | no | **Admin**, `fix_surface: connect-store`. |
| `present-undeclared` | **Present on GitHub beyond the brief** (extra dept, second harness). | calm neutral + "not in your plan, and that's fine". | no | none, `fix_surface: none`. |

**Fail-closed rule.** An unreadable or missing **security-adjacent** field (repo visibility, base
permission, store reachability, a malformed row) ⇒ the verb emits `unknown` for that check, never
`pass`; and a missing/malformed `schema_version` or `status` ⇒ the app refuses the whole payload
(per the cli-contract global rule). `unknown` is never coerced to green.

### 3.3 Check inventory (harness-aware, derived from the brief)

For a brief with harness list `H` and departments `D`:

| `check` id | Passes when | `owner` on fail/unknown | `fix_surface` |
|---|---|---|---|
| `org-triplet` | for each `h` in `H`, `<org>/<h>-copilot-internal` exists; and `<org>/knowledge-copilot-internal`, `<org>/cli-copilot-internal` exist; all private. | Admin | describe |
| `org-base-read` | org `default_repository_permission = read`. | GitHub org owner | external |
| `dept-triplet` (one row per dept) | for dept `d`: for each `h` in `H`, `<h>-copilot-<d>` exists; and `knowledge-copilot-<d>`, `cli-copilot-<d>` exist. | Admin | describe |
| `dept-team-grant` (one row per dept) | team `<org>/<d>` exists **and** grants read/write on its whole triplet. | Admin | describe |
| `ecosystem-file` | `ecosystem.yml` exists in `<org>/<harness>-copilot-internal`, parses, and matches the brief (org, harness set, departments, store status). | Admin | describe |
| `store` | connected -> the endpoint answers and team_scopes map; **deferred -> `deferred`** (neutral). | IT infra (connected) / Admin (deferred) | connect-store |
| `foundation-pin:<harness>` | each product-specific, version-pinned anon-HTTPS foundation reference resolves. | ENAC/external | external |
| `github-app` | `ecosystem.yml` carries the same well-formed public `github_app.client_id` as the brief. | Admin | describe |
| `personal-handoff` | `ecosystem.yml` declares user-owned personal onboarding for every harness, rank 10, without a personal repo URL, credential, or content pointer. | Admin | describe |

**Drift rows are emitted, not inferred by the app.** A department or a second harness present on
GitHub but absent from the brief emits a `present-undeclared` `dept-triplet`/`org-triplet` row; the
app renders it calm. The `store` row is the only one that can carry `deferred`. A re-run against an
already-standing org reads as a column of `pass` with `must_fix: 0`.

The `github-app` and `personal-handoff` checks are independently visible even though both values
live in `ecosystem.yml`. While an ecosystem PR is awaiting review, all affected rows remain
`fail`; they become `pass` only after the values are present on the default branch.

---

## 4. `ecosystem.yml` v-next

The org's config-of-record, written once and living forever, that every user's copilot CLI
resolver reads.

**Home.** **DECISION (owner-ratified, sd §7.1):** the **org-level harness component repo**
(`<org>/<harness>-copilot-internal`) — the instruction layer every user inherits. For a two-harness org the
canonical copy lives in the first-declared harness repo; the second-harness re-run keeps it there
(it is not duplicated per component).

**Schema** (`schema_version: "2.0"` — the major bump marks the break from the integration-carrying
v1):

```yaml
schema_version: "2.0"
org: acme-co
harness:                    # LIST; second-harness re-run appends additively
  - codex
components:                 # the fixed CSE component set present at every layer
  - knowledge
  - cli
  - codex                   # the harness component(s); mirrors `harness`
departments:
  - unit: accounting
    topology: separate      # DEFAULT (four-tier §6.2); `subfolder` is an explicit opt-out only
  - unit: sales
    topology: separate
store:
  status: connected         # connected | deferred
  type: infisical
  endpoint: https://vault.acme-co.com
  workspace_id: "workspace-acme"
  environment: prod
  secret_path: "/shared"
  team_scopes:
    - { team: accounting, scope: dept/accounting }
    - { team: sales,      scope: dept/sales }
github_app:                 # the company's OWN GitHub OAuth App (§1.6)
  client_id: Iv1.a1b2c3d4e5f6a7b8   # PUBLIC; users' device-flow sign-in reads it, secret unused
foundation:
  refs:                      # product-specific pins applied by the script
    claude: "^5.8.0"
    codex: "^0.6.0"
personal:
  owner: user                # Admin never creates or owns this layer
  rank: 10
  repository_pattern: "<user>/<component>-copilot-private"
```

Deferred store: `store: { status: deferred }` (no endpoint, no team_scopes).

**`github_app.client_id`** is the company's own OAuth App identifier (§1.6). It is **public config,
not a secret**: it is the one field here that every user install reads, so their "Connect GitHub"
device flow runs through the company's own app. The engine writes it verbatim from the brief; the
client secret never enters the brief, this file, or any repo (invariant #6).

**`personal` is a handoff contract, not a personal declaration.** It tells User
Setup how to create or select user-owned repositories after personal sign-in. It
must not contain a username, repository URL, token, key, or content path. The
effective no-department ranks are personal 10, organization 30, foundation 40.

**Additive-merge on re-run.** The script re-authors `ecosystem.yml` by **adding** entries and
**never rewriting** existing ones: a new department appends to `departments`; the second harness
appends to `harness` + `components`; connecting a deferred store flips `store.status` and adds the
pointer. Existing entries are left byte-for-byte where the shape already matches.

**What it NO LONGER carries, and the superseding mechanism:**

| Removed from v1 | Superseded by |
|---|---|
| `integrations:` (per-layer declarations + `requires_secret` + `store_scope`) | The **per-repo integration registry manifest** (§5), gated by entitlement. Absence-equals-non-existence relocates from this central file to the distributed registries. |
| `policy_signers:` | **GitHub branch protection** configured by the engine script (§6 step 3/4d): private repos + required reviews. Policy signing is deferred entirely from v1 (no panel, no concept). |

---

## 5. The integration registry manifest

The distributed home of "which integrations exist," gated by entitlement. Authored by department
engineers in Journey B; the admin app renders it read-only.

**Location.** **DECISION:** one registry per layer, living **only in that layer's `cli-copilot`
component repo** (org: `<org>/cli-copilot-internal`; dept: `<org>/cli-copilot-<unit>`), **not** per
component. Rationale: an integration is, by the CSE model, a **CLI Copilot / integration-layer**
artifact (a small CLI tool that reaches an outside system); a registry per component would scatter
one concept across three repos for no gain, and the approved design's own mock places it at
`acme-co/cli-copilot-sales · registry` (interaction-design Surface 6). Filename:
`integrations.registry.json` at the repo root.

**Schema** (`schema_version: "1.0"`):

```json
{
  "schema_version": "1.0",
  "integrations": [
    {
      "id": "salesforce-lookup",
      "name": "Salesforce lookup",
      "description": "Reads Salesforce records a copilot can cite.",
      "requires_secret": "SALESFORCE_API_KEY",
      "store_scope": "dept/sales",
      "introduced_by": "acme-co/cli-copilot-sales"
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string (slug) | Stable identifier, unique within the registry. |
| `name` / `description` | string | Human-facing. |
| `requires_secret` | string (NAME) | **A name, never a value.** Resolves against the inherited store endpoint. |
| `store_scope` | string | Which store scope holds the secret (maps to `ecosystem.yml` `team_scopes`). |
| `introduced_by` | string (repo) | **DECISION: date-free provenance** — the publishing repo, no timestamp. Git already carries the authoritative date/author of the merge commit; a redundant field only drifts. |

**Publish semantics.** Presence on `main` = published; **absence = non-existence**. There is no
"published" flag and no retirement tombstone: retiring an integration is removing its entry and
re-merging (plus rotating its key in the store).

**Consumer contract.**
- **User-face app:** renders the **union** of registries across the repos the user is entitled to
  (has GitHub read on), and MAY notify when a new entry appears in an entitled registry. An
  unentitled or unpublished integration is invisible, exactly as the old central declaration made
  it invisible, just relocated.
- **Admin app (Org setup, Surface 15):** renders the same union **read-only**; it never authors or
  edits a registry.

**Secret invariant.** A registry entry **never** carries a secret value — only the `requires_secret`
NAME and the `store_scope`.

---

## 6. Engine script obligations (delta)

The updated ordered step list the idempotent `gh` script (freeze target:
`copilot admin bootstrap`) MUST implement. Every mutation is **check-then-act** (GET before
POST/PATCH/PUT). The script, not the model, makes every decision.

| # | Step | Mechanism | Idempotency |
|---|---|---|---|
| 0 | **Preflight auth + scope** | `gh auth status`; actor is an **owner** of `<org>`; scopes `repo` + `admin:org`. | **Refuses** (exit 2, plain instruction, teaches `gh auth refresh -s admin:org -s repo`) if any fail. No mutation before this passes. |
| 1 | **Org base permission = read** | `PATCH /orgs/{org} -f default_repository_permission=read`. | Set-to-value no-op if already `read`. |
| 2 | **Create the org triplet** | for each `h` in harness: GET-then-POST `<org>/<h>-copilot-internal`; plus `<org>/knowledge-copilot-internal`, `<org>/cli-copilot-internal` (all **private**). | Existing repo with content -> `already-present`, never clobbered. |
| 3 | **Initialize organization harness packages + protect** | After the handoff write, seed a minimal rank-30 `copilot.layer.yml` only in a confirmed-empty harness repository or the engine's known-safe handoff branch, then require PR review. | A valid existing package is reused; unfamiliar content or a different manifest is refused, never overwritten. |
| 4 | **Per department (loop)** | 4a create triplet `<h>-copilot-<unit>` (each `h`), `knowledge-copilot-<unit>`, `cli-copilot-<unit>` (private); 4b create team `<org>/<unit>`; 4c grant the team its whole triplet; 4d seed minimal rank-20 harness packages only in confirmed-empty repos; 4e branch protection. | Existing package/repo/team -> `already-present`; unfamiliar content holds; grant/protection are idempotent. |
| 5 | **Write/update `ecosystem.yml`** | Additive merge (§4) into `<org>/<harness>-copilot-internal`: components, departments (`topology: separate` default), harness list, store pointer, **the company GitHub app's public `client_id`** (§1.6), product-specific foundation pins, and the non-secret personal handoff. Initial commit on an empty repo; PR once the repo carries content. | Re-run **adds** a new dept/harness/store entry or first-time public client id/handoff; **never rewrites** an existing organization identity, personal ownership rule, or foundation pin. |
| 6 | **Fail-closed leak-scan** | Run the leak-scan over `ecosystem.yml` **before any push** (deny-list: key prefixes, `BEGIN PRIVATE KEY`, `.env` shapes, high entropy). | A secret-shaped value -> **refuse to push** (invariant #6). The file carries only the non-secret endpoint + `requires_secret`-free content. |

**Explicitly NOT steps (killed):**
- **No team-member provisioning.** GitHub is the only user-management surface; the script creates
  the team and the grant that *makes joining possible*, never adds/removes people (design
  principle 5). (Removes the old §1.3 step 3c.)
- **No integration writes.** The script never authors a registry; integrations arrive via Journey
  B, authored by department engineers. (Removes the old §2 seed `integrations` block.)
- **No policy-signer / capability-policy signing.** Deferred from v1; branch protection (steps
  3/4d) is the v1 control.

**Re-run shapes.**
- **Add a department:** runs steps 4-6 for the one unit + the base steps as no-ops; existing units
  are a full no-op.
- **Add the second harness:** steps 2/3 create the new `<h>-copilot-internal` repos additively, step 4a
  adds each department's second-harness repo, step 5 appends `harness`/`components`; everything
  else `already-present`.
- **Connect the store later:** step 5 flips `store.status` and adds the pointer; step 6 re-scans.

**Emitted stream vocabulary.** Each step emits `{step, result, detail}` (consumed by Claude Code's
narration, not the app):

| `result` | Meaning | Narrated as |
|---|---|---|
| `created` | A new repo/team was made. | "Created ..." |
| `already-present` | Existed at the desired state; untouched. | "Already there." |
| `updated` | An idempotent set brought a value to desired (base perm, grant, branch protection, an added `ecosystem.yml` entry). | "Set ..." |
| `skipped` | Not applicable this run. | "Skipped." |
| `refused` | A gate refused (missing scope at step 0, leak-scan trip at step 6). **Fail-closed: no mutation past it.** | "Stopped: <reason>." |
| `failed` | One step errored; prior additive steps intact; safe to re-run. | plain `detail` + owner. |

**DECISION:** `updated` is added to the frozen `created|already-present|skipped|refused|failed`
vocabulary so idempotent set-to-value operations (base permission, grants, branch protection,
appended config entries) narrate honestly as "set," not miscoded as `created`.

---

## 7. Superseded-sections reconciliation

So a developer never builds from a stale paragraph. Status: **current** / **superseded-by**.

### 7.1 `docs/03-design/admin-agentic-setup.md`

| Section | Status |
|---|---|
| §0 Vocabulary (component/layer/tier/entitlement) | **Current.** |
| §1.1 Skill(face)+CLI(engine) split; three-faces-one-engine | **Current.** |
| §1.2 Interim `gh` script -> `copilot admin bootstrap` at freeze | **Current** (see §6/§8 here). |
| §1.3 GitHub sequence — **naming** (`copilot-org`, `copilot-dept-<unit>`) | **Superseded by** §6 here: component-first naming — org layer `<org>/<C>-copilot-internal`, department `<org>/<C>-copilot-<unit>`, foundation (public, read-only) `Everyone-Needs-A-Copilot/<C>-copilot`. |
| §1.3 step 3c **team-member provisioning** | **Superseded by** §6 (killed — GitHub is the user-management surface). |
| §1.3 step 4 seed carries `policy_signers` + per-layer `integrations` | **Superseded by** §4 (`ecosystem.yml` v2 drops both) + §5 (registries) + §6 step 3/4d (branch protection). |
| §1.3 single-repo-per-tier model | **Superseded by** §4/§6: a **triplet** (3 components) per layer. |
| §1.4 Safety (owner rights, never-create-org, never-clobber, no personal tier, leak-scan) | **Current.** |
| §2 Integration management **in the seed** | **Superseded by** §5: integrations leave `ecosystem.yml` entirely; existence lives in per-repo registries. |
| §3 Parse-never-compute Admin seam | **Current** in principle; the specific "app fires bootstrap and streams rows" is **superseded by** the baton pass (app writes brief + copyable command; §1/§2 here). |
| §4 Setup verification grammar | **Current, extended** by §3 here: adds `deferred` + `present-undeclared` statuses and `fix_surface`; drops the "seed signed by policy_signer" check. |
| §5 Open decisions | Q1/Q2 **current** (WS-A fold, §8); Q3 (`admin:org` acquisition) **current/open**; Q4 fresh-repo seed delivery **current** (§6 step 5); Q5 integration classification **superseded/moot** (admin declares none). |
| §6 Invariant conformance | **Current.** |

### 7.2 `docs/03-design/control-tower-admin-flow.md`

| Section | Status |
|---|---|
| §0 Reframe (drive-the-agent), §1 JTBD | **Current** in spirit; the "app fires one bootstrap and renders streamed rows" is **superseded by** the baton pass (app is blind during execution; narration is Claude Code's). |
| §2 Surface inventory (ADM-0..G3) | **Superseded by** the 16-surface inventory in the interaction design; map ADM-* via the sd §6 delta table. |
| §5 ADM-3 Connect GitHub (refuse-and-teach, no bypass) | **Current** (now advisory, not a hard gate; interaction-design §1.3). |
| §6 ADM-4 members/team-grant sub-panel, integration-per-layer declaration | **Superseded** (killed; §5 + §6 here). |
| §6.2/§6.4 ADM-6 Seed generator form, ADM-7 Policy signers | **Superseded** (killed; the script writes `ecosystem.yml`; no signing). |
| §7 ADM-8 Review **& run** (app fires + streams `{step,result}` in-GUI) | **Superseded by** Review **and hand off** (§1/§2) + the blind Handed-off state; the streamed vocabulary relocates to §6 (terminal narration). |
| §8 ADM-9 Preflight grammar (row/status/owner/count) | **Current, renamed** Setup check; extended by §3 here. |
| §9 ADM-G1 Deprovision (rendered revocation+rotation) | **Superseded by** "Someone left" (instructional; app renders teams + keys to rotate, triggers nothing). |
| §9 ADM-G3 Secret store config panel | **Superseded** (merged into read-only Org setup, Surface 15). |
| §10 ADM-SKILL as an "alternative" path | **Superseded**: the terminal is *the* execution path, not an alternative. |
| §11 drive-and-render seam table | **Superseded** where it shows the app firing/streaming; the collect/render split is **current**. |
| §15 Invariant conformance | **Current.** |

**Naming note (non-reconciliation-table, but load-bearing):** `four-tier-topology.md` remains
authoritative for resolver/teams/auth **mechanics**, but its illustrative repo names
(`copilot-org`, `copilot-dept-<unit>`, single repo per tier) are superseded by the owner-ratified
**component-first** naming and the **triplet-per-layer** matrix used throughout this contract.

**Component-first naming convention (owner-ratified 2026-07-16 — universal, load-bearing).**
For `<C>` ∈ {`<harness>`, `knowledge`, `cli`}:

| Layer | Repo | Visibility | Read as |
|---|---|---|---|
| Foundation | `Everyone-Needs-A-Copilot/<C>-copilot` | public | anon HTTPS (bare name, never suffixed) |
| Org | `<org>/<C>-copilot-internal` | private | the org's own layer |
| Department | `<org>/<C>-copilot-<unit>` | private | one triplet per department |

`internal` is a **fixed literal**, not the org name, so the org layer never collides with the
foundation and both can live in one org (the ENAC/publisher case). It is therefore a **reserved
department slug**: the engine refuses a department named `internal`, and the undeclared-department
scanner skips `<C>-copilot-internal` (it is the org layer, not a department).

---

## 8. WS-A alignment note

Every verb and schema defined here is **control-tower-originated** — the same status as
`copilot publish` and `copilot layers` in `cli-contract.md` (designed in this repo, not yet in
upstream WS-A scope). They **fold into WS-A at freeze**, when the interim `gh` script's `--verify`
mode migrates into `copilot admin bootstrap --verify --json` with no guarantee changing hands
(the guarantees were always in deterministic code; only its home moves).

Accordingly:
- **Carry `schema_version` from day one** (brief `1.0`, verify `1.0`, `ecosystem.yml` `2.0`,
  registry `1.0`), `MAJOR.MINOR[.PATCH]`, range-gated both directions per `_envelope.schema.json`.
- **Fail-closed everywhere security-adjacent** (§3.2): a missing/unreadable security field is
  `unknown`/refuse, never green/safe.
- When WS-A is built, add `admin-bootstrap.verify.schema.json` to `docs/01-architecture/schemas/`
  and wire it into the CI contract test alongside the existing verbs; reconcile this prose with the
  real CLI (schemas win for machines).

---

*Route to @agent-me for implementation of the three build targets against this contract (the app's
brief-writer + verify-renderer + registry roll-up; the `admin-bootstrap` skill; the idempotent gh
script). Route to @agent-qa for the contract test that asserts the verify JSON, the brief
front-matter, and `ecosystem.yml` v2 against these schemas. The baton pass (brief -> terminal ->
verify) remains the single untested moment the sd flagged for one real-operator validation.*
