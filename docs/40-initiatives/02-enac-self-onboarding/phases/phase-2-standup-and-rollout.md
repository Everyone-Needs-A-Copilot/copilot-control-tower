# Phase 2 — Stand up, wire, validate, roll out

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-1-public-base-extraction.md`](phase-1-public-base-extraction.md)
> (the `-internal` split done, base repos curated and still private).

This is the execution runbook. Every stage is tagged by reversibility. The one
irreversible act — making the base repos public — is the last, gated step.

## Step A — machine-global snapshot (safety, before any run)

The run touches three **machine-global** surfaces (not per-project). Snapshot
first:

- `~/.claude/cc/config.json` — bootstrap writes layer pointers / `layers.department`.
- `~/.ssh/config` — the host aliases in Step B are a global edit.
- Keychain: note any entry under `com.everyoneneedsacopilot.copilot.github` — the
  GitHub token lives in **one** slot, so a new sign-in re-keys it (re-auth to
  switch identities; not destructive).

## Step B — stand up the org layer *(additive / idempotent / reversible)*

Prerequisites (owner or developer):

- **`gh auth refresh -s admin:org -s repo`** — current token lacks `admin:org`.
- **ENAC's own GitHub OAuth App** — org → Settings → Developer settings → OAuth
  Apps → New OAuth App; enable **Device Flow**; ignore the client secret; copy the
  **Client ID** (`Iv1.`+16 hex, or 20-char hex). Public; travels in `ecosystem.yml`.

Brief (`~/Library/Application Support/CopilotControlTower/standup-brief.md`):

```yaml
---
schema_version: "1.0"
org: Everyone-Needs-A-Copilot     # the ONE org — foundation and org layer both live here
                                  # (org layer repos are <C>-copilot-internal; no extra brief field)
harness: [claude]                 # add codex later as a second-harness re-run
departments: []                   # start empty
store: { status: deferred }
github_app: { client_id: <ENAC_CLIENT_ID> }
contacts:
  publisher: "Pablo Alejo"
  admin: "Pablo Alejo"
  point_of_contact: "pablitoalejo@gmail.com"
---
```

Run order:

1. **Dry run (read-only, zero mutation):**
   `scripts/admin_bootstrap.sh --verify --json --brief <path>`. The NDJSON is the
   plan-of-record of what a real run *would* create.
2. **Real run (additive/idempotent):**
   `scripts/admin_bootstrap.sh --brief <path>`. Creates any missing
   `<C>-copilot-internal` repos, sets branch protection, authors `ecosystem.yml`
   (with the client id). Re-runnable as a no-op; never `--force`.

> **Known engine gaps to watch** (from prior audit): a phantom
> `<org>/copilot-ecosystem` reference; ~25 docs linking to non-existent
> `docs/reference/` (real: `docs/10-reference/`); `native/admin.swift:196–206`
> resolves engine/skill paths from cwd (breaks when packaged — use
> `Bundle.main.resourcePath`). Fix these alongside the run.

## Step C — manifest wiring *(config only / reversible)*

`copilot.layers.yml` for the `claude` component (repeat per component):

```yaml
version: 1
layers:
  - id: personal-pablo
    role: personal
    component: claude
    rank: 10
    source: { repo: git@github-personal:pablitoalejo/claude-copilot-private.git, ref: main }
    auth: ssh-personal
    activation: always
  - id: org-enac
    role: org
    component: claude
    rank: 30
    source: { repo: git@github-work:Everyone-Needs-A-Copilot/claude-copilot-internal.git, ref: main }
    auth: ssh-work
  - id: foundation
    role: foundation
    component: claude
    rank: 40
    source: { repo: https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git, ref: ^5.8.0 }
    auth: anon
```

**The subtlety of one org:** the org layer and foundation live in the *same* GitHub
org but are **different repos with different transports** — the org layer is a
**private** repo over **`ssh-work`** (the key must have access to the `-internal`
repos); the foundation is a **public** repo over **anon HTTPS**. SSH host aliases
are still required because personal and work identities both resolve `github.com`
and would otherwise collide (topology §6.1):

```sshconfig
Host github-personal
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
Host github-work
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
```

## Step D — validate on a scratch project *(the safety gate — no real work at risk)*

One throwaway repo. `copilot update` materializes `.claude/`. Prove three things
before touching any real project:

- resolution/shadowing correct — `resolve --explain` shows org shadowing
  foundation, personal shadowing org;
- ENAC's mature org content actually appears;
- **never-destroy holds** — dirty the tree, re-run, confirm hold-on-dirty with zero
  writes.

## Step E — roll to real products, one at a time *(never-destroy protected — the payoff)*

Start with a single product, committed clean first. `copilot update`, then inspect:
`.claude/` correct, `git diff` sane, working tree untouched. Then fan out to the
rest — this is the "update once, every project follows" payoff. **Re-point any
consumer that referenced the old `knowledge-copilot`/`cli-copilot` names** here,
per the Phase 1 rename-redirect hazard.

## Step F — publicize the base *(SEPARATE, one-way, gated)*

Only after Steps D–E are green. Flip the curated `knowledge-copilot` and
`cli-copilot` base repos from private → **public**. Single irreversible act (public
= assume indexed forever), its own deliberate decision, decoupled from everything
above.

- `cli-copilot` is easier — binary; confirm the repo carries no secrets, then flip.
- `knowledge-copilot` — flip only after the Phase 1 leak-scan and base-curation
  pass.

## §9 — Hand-off checklist for the developer

- [x] Engine change: org layer → `<C>-copilot-internal`; foundation read stays
  bare; reserve `internal` as a dept slug + skip it in the undeclared-dept scanner;
  `test_admin_bootstrap.sh` green. **(Done this session — 142/142.)**
- [ ] Fix the phantom `copilot-ecosystem` ref, the `docs/reference/` links, and the
  `admin.swift` cwd path (Step B).
- [ ] Phase 1: base-extraction for `knowledge-copilot`, then `cli-copilot`
  (rename → `-internal`, create private base, curate + leak-scan).
- [ ] Snapshot the three machine-global surfaces (Step A).
- [ ] `gh auth refresh -s admin:org -s repo`; create ENAC OAuth App; fill the brief
  (Step B).
- [ ] Dry-run `--verify --json`, review, then the real `--brief` run (Step B).
- [ ] Wire `copilot.layers.yml` + SSH aliases per component (Step C).
- [ ] Validate on scratch (`resolve --explain`, never-destroy) (Step D).
- [ ] Roll to real products one at a time; re-point old-name consumers (Step E).
- [ ] Gated, last: flip the base repos public (Step F).

## Acceptance

A clean machine cloning only the public bases gets a working generic ecosystem;
ENAC's own machine, with the `-internal` org layer stacked on top, resolves to the
full mature content it has today; and a single `copilot update` propagates a
component change to every ENAC project.
