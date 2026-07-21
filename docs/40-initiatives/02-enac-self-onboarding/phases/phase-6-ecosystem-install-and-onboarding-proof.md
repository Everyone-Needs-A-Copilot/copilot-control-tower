# Phase 6 — Ecosystem install + two-machine onboarding proof (hand-off)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-4-tier-completion-handoff.md`](phase-4-tier-completion-handoff.md)
> (tier runtime + credential ladder + config inheritance + `copilot update`
> mirror-sync — shipped, live, pushed) and the **Phase 5 org-config-migration
> cutover** (2026-07-21: org `.env` emptied; non-secret config → committed
> `cli.overlay.yml config:` blocks; secrets → Infisical + keychain; org mirror is
> now a clean git clone — recorded in the `phase-5(…)` commits, WP-79, and the
> session memory `phase-5-org-config-migration`).
> **Taking this over in a new conversation? Read this doc top-to-bottom, then
> Phase 4, then Phase 3, then the session memory `cli-tier-inheritance-live.md`.
> Everything here is additive and reversible; the tier is already live on ENAC's
> Mac.**

## Status (one paragraph)

Phases 1–5 delivered the hard machinery: the public foundation / private
`-internal` org split (Phase 1, pushed), the GitHub standup engine
(`scripts/admin_bootstrap.sh`, 142/142 tests — Phase 2), the live **base +
org-overlay tier runtime** with a fail-closed credential ladder (Phase 3), then
**config inheritance** (`TierConfigSource` + committed `config:` blocks), the
**`copilot update` mirror-sync verb** (never-destroy, semver-range resolver,
versioned `--json`), per-secret routing (Phase 4), and the **org-config
migration + cutover** (Phase 5). The 2026-07-21 CLI cutover emptied
`cli-copilot-internal/.env` entirely: store config now travels in the committed
`cli.overlay.yml`, secrets resolve from Infisical + keychain, and `copilot
update` regenerates the org mirror from a clean git clone with **no `.env` at
all**. Verified live on ENAC's Mac (zero fail-closed). **This phase does not
build more tier machinery — it proves the whole thing can be *installed and
onboarded end-to-end*: admin configured on this machine, the user app installed
on this machine, and — the real test — the user app installed on a laptop that
starts empty and inherits the same tier with as close to one command as today's
tooling allows.** The gaps this phase exposes are almost entirely
*install/onboarding* gaps (app packaging, manifest delivery, CLI install,
machine-identity bootstrap-cred provisioning, laptop SSH key), not tier-runtime
gaps.

---

## 1. The end state we are validating

Three machines, one tier, no `.env`, everything regenerable:

1. **Admin configured (this machine).** `Everyone-Needs-A-Copilot` carries the
   private `<C>-copilot-internal` org triplet + branch protection + a matching
   `ecosystem.yml`, the managed secret store (Infisical at
   `secrets.ineedacopilot.com`) holds the org secrets, and the company GitHub
   OAuth App exists (device-flow enabled, client id public).
2. **User app on this machine.** The signed/notarized Control Tower user app is
   installed, supervises the `cc`/`copilot` CLI, renders honest `--json` status,
   and the CLI resolves the full mature ENAC ecosystem via **org overlay (rank
   30) + public foundation (rank 40, `^0.3.0` → `v0.3.0`)** with every secret
   resolving through the ladder and **zero secrets in any `.env`**.
3. **User app on the laptop (second machine).** A machine that started with an
   empty keychain and no work SSH key onboards, `copilot update` clones both
   mirrors, and every service resolves from the inherited config + store with no
   hand-copied `.env` — proving the tier is *inheritable*, not *hand-wired*.

**Acceptance for the whole phase:** on the laptop, from a cold start,
`copilot --json layers` shows `org-internal (30) → foundation (40)`,
`copilot update --json` reports `overall: ok` with both mirrors `cloned`/`pulled`
and store-readiness `ready`, and a store-backed service (e.g. `copilot uspto
health`) is healthy — with **no secret and no store config ever hand-typed into a
file**, only the machine-identity bootstrap creds placed in the laptop keychain
and the laptop's own SSH key registered to GitHub.

---

## 2. Prerequisites — what must be true first

| # | Prerequisite | State today | Source |
|---|---|---|---|
| P-1 | GitHub org `Everyone-Needs-A-Copilot` exists; operator is an Owner. | True (live). | `admin-prerequisites.md` |
| P-2 | `gh` signed in with `repo` + `admin:org` scopes. | The token has historically lacked `admin:org`; run `gh auth refresh -s admin:org -s repo`. | Phase 2 Step B; `admin-prerequisites.md` |
| P-3 | Company GitHub **OAuth App** (device flow on; client id is public config). | Must be created once at github.com → org → Developer settings → OAuth Apps. | `admin-standup-contract.md §1.6` |
| P-4 | Managed secret store (Infisical) reachable at `secrets.ineedacopilot.com`, org secrets populated. | Live; org secrets in `copilot-ecosystem/prod/shared`. | Phase 3; `05-scoped-identities-handoff.md` |
| P-5 | Public foundation pin resolves. `cli` foundation is `^0.3.0`; tags `v0.1.0/v0.2.0/v0.3.0` exist and `origin/main` is current. | True (probed). **Note:** the earlier `^5.13.0` hazard was for the *content* foundation (claude/knowledge); `admin_bootstrap.sh` now defaults `FOUNDATION_REF_DEFAULT="^5.8.0"` (resolves to `v5.8.0`). `codex-copilot` still has **no tags**, so a Codex-shop `foundation-pin` check fails — ENAC is a `claude` shop, so this is not blocking here but must be flagged before any Codex standup. | live probe; `admin_bootstrap.sh:30` |
| P-6 | Both CLI repos are **pushed** so a laptop can clone them. | True: `cli-copilot` and `cli-copilot-internal` are both even with `origin/main` (probed). The private org repo is cloned over `ssh-work` per the manifest. | live probe |
| P-7 | App signing/notarization credentials for distribution. | **Missing** — Apple Developer ID cert, notarytool creds, and minisign custody are all owner-gated and not on this machine; the two native binaries have never been packaged/notarized. | `m4-distribution-decisions.md`; `native-app-rebuilt.md` |

---

## 3. Step 1 — Admin on this machine

**Goal:** stand up / confirm ENAC's org tier so a user app on any machine has a
real tier to inherit. This is Phase 2 executed for real (do not re-plan it —
reference `phase-2-standup-and-rollout.md` Steps A–E).

### Tasks

- **S1-T1 — Machine-global snapshot** (Phase 2 Step A). Snapshot
  `~/.claude/cc/config.json`, `~/.ssh/config`, and the single GitHub-token
  keychain slot before any run. *Complexity: Low.*
- **S1-T2 — GitHub readiness** (Phase 2 Step B / `admin-bootstrap` SKILL §3).
  `gh auth refresh -s admin:org -s repo`; create the ENAC OAuth App; capture its
  client id. *Complexity: Low.*
- **S1-T3 — Write the standup brief.** At the fixed app-owned path
  `~/Library/Application Support/CopilotControlTower/standup-brief.md`
  (`admin-standup-contract.md §1.1`): `org: Everyone-Needs-A-Copilot`,
  `harness: [claude]`, `departments: []`, `store: connected` (Infisical endpoint,
  the ENAC scope mapping), `github_app.client_id`. *Complexity: Low.*
- **S1-T4 — Dry run then real run.** `bash scripts/admin_bootstrap.sh --verify
  --json --brief <path>` (read-only plan-of-record), review, then
  `bash scripts/admin_bootstrap.sh --brief <path>` (additive/idempotent). Creates
  missing `<C>-copilot-internal` repos, sets branch protection, authors
  `ecosystem.yml` v2.0. *Complexity: Medium.*
- **S1-T5 — Fix the three known engine gaps** alongside the run (Phase 2 Step B
  "Known engine gaps"): the phantom `<org>/copilot-ecosystem` ref, the
  ~25 `docs/reference/` links (real: `docs/10-reference/`), and
  `native/admin.swift`'s cwd-relative engine/skill path resolution (must use
  `Bundle.main.resourcePath` when packaged). *Complexity: Medium.*
- **S1-T6 — Setup check (verify verb).** Re-run `--verify --json`; confirm a
  clean column of `pass` with `must_fix: 0`. *Complexity: Low.*

### What it provisions

Private `knowledge-copilot-internal` / `cli-copilot-internal` / (harness)
`claude-copilot-internal` repos in `Everyone-Needs-A-Copilot`, branch protection,
`ecosystem.yml` v2.0 (org, harness list, components, departments, store pointer,
`github_app.client_id`, foundation pin), org base permission `read`. It does
**not** provision people, integrations, or secrets — those live in GitHub team
membership, per-repo registries, and Infisical respectively.

### Acceptance

Verify verb returns all-`pass`, `must_fix: 0`; the three `-internal` repos exist
private with branch protection; `ecosystem.yml` parses and matches the brief; the
leak-scan passed before push (invariant #6).

### Decisions

- **D1 (this-machine reality vs. shipped path).** The store is *already* connected
  and secrets already migrated on this machine (Phase 3). So S1 here is mostly a
  **confirm/verify**, not a fresh standup. Decide whether to run the engine at all
  or only `--verify` — recommend `--verify` first, then a real run only if it
  surfaces `fail`/`present-undeclared` drift.
- **D2 (naming).** `internal` is a reserved literal dept slug; foundation reads
  stay bare (`<C>-copilot`). Already enforced by the engine — no action, just do
  not regress it.

---

## 4. Step 2 — User app on this machine

**Goal:** install the always-on user Control Tower app and confirm it supervises
the already-live tier.

### What exists today

- Two native SwiftUI executables build green: `scripts/build-user.command`
  (admin code not compiled in) and `build-admin.command` (`-D CT_ADMIN_BUILD`);
  9-step wizard + tray de-mocked against the real CLI seam; smoke suites S1–S17
  green (`native-app-rebuilt.md`, commit `66916c6`).
- The app **locates but does not install** the CLI: `CliLocator` (`native/
  cli-client.swift:51`) resolves an absolute `cc` path, checking `CT_CLI_PATH`
  override, then `~/.local/bin/cc`, `/opt/homebrew/bin/cc`, `/usr/local/bin/cc`.
- The wizard drives the CLI, never `Process` directly (`wizard.swift:22–40`):
  step 2 Connect GitHub = `authLoginInitiate()`/`authLoginPoll()` (device flow),
  step 3 Detect = `authStatus()` + `doctor()`, step 5 Departments =
  `layers()`/`layersJoin(id:)`, step 8 Verify = `doctor()`.
- Self-update / crash-only watchdog / rollback / signature-verify are **designed
  and built against dev keys/mocks** but not shipped signed (`m4-distribution-
  decisions.md`).

### Install path (this machine)

1. **S2-T1 — Package + sign + notarize the user binary.** Run the proven pipeline
   (`scripts/sign.sh` + `scripts/notarize.sh`; pipeline validated end-to-end
   2026-07-09 per memory `publish-pipeline-validated`). **Blocked on P-7**
   (Apple cert / notarytool creds). *Complexity: Medium; blocked.*
2. **S2-T2 — Install the app** (drag-to-Applications or a notarized `.dmg`) and
   launch; `launchd` crash-only watchdog registers. *Complexity: Low.*
3. **S2-T3 — First-run wizard.** Connect GitHub (device flow), detect entitled
   layers, join the org layer. *Complexity: Low.*

### First-run behavior — **[VERIFY] the load-bearing unknown**

The plan hinges on *what the wizard actually does to place the tier*, and this is
the least-confirmed area. Two sub-questions to answer by reading the wizard/CLI
seam before building on it:

- **Does the app write `~/.config/copilot/copilot.layers.yml`?** The wizard calls
  `layersJoin(id:)` at step 5. On this machine the manifest was placed **by hand**
  (`cli-tier-inheritance-live.md`). It is unconfirmed whether `layersJoin` (or any
  `cc` verb it shells) *writes the manifest*, or only records a joined-layer
  intent the app renders. **[VERIFY]** — trace `layersJoin` → the `cc` verb → does
  it emit/append a manifest entry?
- **Does the app run `copilot update` on first run / on cadence?** Product-brief
  and architecture say the supervisor pulls on a cadence. The tray polls
  `doctor()` every 300 s (`native-app-rebuilt.md`), but whether it invokes the
  mirror-sync `update` verb (vs. only reading status) is unconfirmed. **[VERIFY]**.
- **The "two CLIs" seam.** The `copilot update` mirror-sync validated in Phase 5
  lives in **`cli-copilot`** (`copilot_cli/main.py:365`, `config/sync.py`). Memory
  `four-programs-two-names` records that **Control Tower's `--json` contract is
  against `claude-copilot`'s `cc`, not CLI Copilot**, and that the docs disagree.
  The shared `copilot.layers.yml` spans all four components, but there may be
  **two distinct `update` verbs** (one per CLI). **[VERIFY / DECISION]** — confirm
  which binary the app shells for `update`, and whether the content components
  (claude/knowledge) have their own sync path the app must also drive.

### Acceptance

App launches, tray renders honest status, wizard completes; after first run
(or a manual `copilot update`), `copilot --json layers` →
`org-internal (30) → foundation (40)`; `copilot update --json` → `overall: ok`,
both mirrors present, store-readiness `ready`; a store-backed service is healthy;
**no secret in any `.env`**.

### Decisions

- **D3 (who owns onboarding — app or CLI).** Either the app wizard writes the
  manifest + triggers `update`, **or** a CLI verb (`copilot init`/`copilot
  onboard`) does it and the app just renders. Recommend the **CLI owns it**
  (invariant #1: parse-never-compute — the app must not compute the manifest), the
  app calls a single `cc` verb. This decision gates whether S3 (laptop) can be
  "one command" at all.

---

## 5. Step 3 — User app on the laptop (the second-machine test)

**Goal:** a machine that starts with an **empty keychain and no work SSH key**
onboards and inherits the exact same tier. This is the honest test of "install,"
and it is where today's tooling is **not yet one command**. Below is the full
cold-start checklist; each line names who/what must provide it and whether it
exists today.

### 5.1 Cold-start bootstrap checklist

| # | The laptop needs… | Provided by | Exists today? |
|---|---|---|---|
| B-1 | The `cc`/`copilot` CLI installed at a `CliLocator` path (`~/.local/bin/cc`, homebrew prefixes). | A pipx/uv install of `cli-copilot` (foundation) + the `copilot-overlay-internal` editable overlay (`pip install -e … --no-deps`, per the overlay-dep gotcha). | **Partial** — installable by hand from the repos; **no packaged installer** and no one-command bootstrap. |
| B-2 | The tier manifest at `~/.config/copilot/copilot.layers.yml` (org rank 30 `ssh-work`, foundation rank 40 `anon`). | Placed by hand today. Should be shipped by the app wizard or a `copilot init` verb (D3). | **Missing as one-command** — hand-placed on this machine. |
| B-3 | SSH access to the **private** `cli-copilot-internal` over the `github-work` alias — a key with org **read**. | A **new, on-device** ed25519 keypair generated on the laptop, its **public** half registered to the owner's GitHub account (which is in the org). Per invariant #6, push creds are per-user on-device — **never copied** from this machine. | **Missing as automation** — `credentials-and-boundary.md §6.1` designs on-device key generation and §6.2 designs `copilot auth rotate-key`, but **generation-at-onboarding is not wired**, and §7 (multi-machine key sync) is an explicit **open design item**. The correct laptop answer per §7 is "each machine keeps its own keypair registered separately under the same GitHub identity" — no key sync needed. |
| B-4 | The `github-work` SSH host alias in `~/.ssh/config`. | Written by the wizard or by hand (Phase 2 Step C sshconfig block). **Note:** this machine uses a single `IdentityFile ~/.ssh/id_ed25519` for `github-work` (not the design's `id_ed25519_work`), and no `github-personal` alias is present — the laptop should follow the *design* (distinct keys per identity) or consciously mirror this machine. | **Missing as automation** — hand-edited global file. |
| B-5 | The Infisical **bootstrap** creds (`INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET`) in the laptop **keychain**. These live ONLY in the per-user keychain, never in git/inheritance (`managed_store.py` `_NEVER_FROM_STORE`, `_read_bootstrap_cred` = keychain-first). | A machine identity. **Today this is the org-wide `ecosystem-admin` identity** whose creds are on this machine's keychain — high blast radius. The intended mechanism is a **scoped, per-machine identity** minted by `copilot infisical identity provision` and written to the laptop keychain. | **Missing** — `infisical identity` exposes only `list` + org-level `create`; `provision` (scoped role + universal-auth + one-time client-secret mint + `--write-env`/keychain) is **not built** (gap-analysis `TASK-INF-2`, G2/G3/G10). |
| B-6 | The store **config** (endpoint, workspace, env, path). | **Inherited** — it travels in the committed `cli.overlay.yml config:` block and `copilot update` clones it into the mirror; `managed_store._find_store_layer` reads it from the composed config, no `.env` needed. | **Done** — config inheritance shipped (Phase 4 #1; verified 3-level). |
| B-7 | `copilot update` to clone both mirrors (never-destroy, semver range → `v0.3.0`). | Built (`config/sync.py`, `main.py:365`). | **Done.** |
| B-8 | The signed user app installed (optional for the CLI proof, required for the product). | S2 pipeline (blocked on P-7). | **Blocked** on signing/notarization. |

### 5.2 The one-command target vs. today's manual steps

**Today (manual), in order:**
1. Install `cc` (foundation) + overlay by hand from the two repos (B-1).
2. Hand-write `~/.config/copilot/copilot.layers.yml` (B-2) and the `github-work`
   ssh-config block (B-4).
3. Generate a laptop SSH key, register its public half on GitHub (B-3).
4. Obtain Infisical bootstrap creds and `security add-generic-password` them into
   the laptop keychain — currently the shared `ecosystem-admin` creds (B-5).
5. `copilot update` (B-7) → verify `layers`, store-readiness, a service health.

**The one-command target:** `copilot onboard --org Everyone-Needs-A-Copilot`
(or the app wizard's equivalent) that: writes the manifest from `ecosystem.yml`,
writes the ssh-config alias, generates + registers the on-device SSH key via the
GitHub device flow (§6.1/§6.2 machinery), drives `copilot infisical identity
provision` to mint a **scoped per-machine** identity and drop its creds in the
laptop keychain, then runs `copilot update` and prints the verify summary. **None
of this orchestration exists yet** — B-1, B-2, B-3, B-4, B-5 are each a separate
manual step, and B-5's `provision` verb is unbuilt.

### 5.3 Tasks to close the laptop gap

- **S3-T1 — Build `copilot infisical identity provision`** (gap-analysis
  `TASK-INF-1`+`TASK-INF-2`): scoped project role (path-scoped CASL DSL, proven
  with the disposable allow/deny test `TASK-INF-3`), universal-auth attach,
  one-time client-secret mint, `--write-env`/keychain-write with redaction. *Unit
  + integration tests required.* *Complexity: High.*
- **S3-T2 — Wire on-device SSH key generation at onboarding** (`credentials-and-
  boundary.md §6.1`): ed25519 keypair generated on the laptop, private half into
  keychain-backed `ssh-agent` (`ssh-add --apple-use-keychain`), public half
  registered via the GitHub device flow (§6.2). Follow §7's "own keypair per
  machine, same identity" — no key sync. *Unit + integration tests required.*
  *Complexity: High.*
- **S3-T3 — Build the onboarding verb / wizard step** that writes the manifest
  (from `ecosystem.yml`), writes the ssh-config alias, and sequences
  S3-T1/S3-T2 + `copilot update`. Decide app-owns vs CLI-owns per D3. *Unit +
  integration tests; UI E2E if app-owned.* *Complexity: High.*
- **S3-T4 — Package a laptop CLI installer** (pipx/uv one-liner or the app bundles
  + installs the CLI on first run). *Complexity: Medium.*
- **S3-T5 — Cold-machine acceptance run** on the real laptop with an empty
  keychain. *Complexity: Medium.*

### Acceptance

On the laptop, from cold: `copilot --json layers` → `org-internal (30) →
foundation (40)`; `copilot update --json` → `overall: ok`, both mirrors
`cloned`, store-readiness `ready`; `copilot uspto health` (or another
store-backed service) healthy; the laptop's own SSH key (not this machine's) is
registered to GitHub and is the only work-push credential; the only secret
material typed on the laptop is the scoped machine-identity bootstrap pair in the
keychain — **no `.env`, no hand-copied secret, no copied SSH private key**.

---

## 6. What's already built vs. missing

| Piece | Status | Gap |
|---|---|---|
| Public/private foundation split, pushed | **Built** | — |
| GitHub standup engine (`admin_bootstrap.sh`), verify verb | **Built** (142/142) | Three known engine gaps (phantom ref, `docs/reference/` links, `admin.swift` cwd path) — S1-T5 |
| `ecosystem.yml` v2.0 authorship | **Built** (engine step 5) | `github-app` verify-check is a v1 contract seam, not implemented |
| Tier runtime (base + overlay, nearest-wins) | **Built + live** | — |
| Credential ladder (store → keychain → device-flow stub → paste) | **Built + live** | Rung 3 device-flow is a clean stub (unbuilt) |
| Config inheritance (committed `config:` blocks, no `.env`) | **Built + live** (Phase 4 #1) | — |
| `copilot update` mirror-sync (never-destroy, semver, `--json`) | **Built + live** | — |
| Secrets in Infisical + keychain, `.env` emptied | **Built + live** (Phase 5 cutover, 2026-07-21) | — |
| Manifest delivery to a new machine | **Missing** | Hand-placed today; no `copilot init`/wizard writer confirmed — B-2, D3 |
| CLI install on a new machine | **Partial** | Hand-installable; no packaged installer/one-liner — B-1, S3-T4 |
| Machine-identity bootstrap-cred provisioning | **Missing** | `infisical identity provision` unbuilt; uses org-wide `ecosystem-admin` — B-5, S3-T1 |
| On-device SSH key gen + GitHub registration at onboarding | **Missing** | Designed (§6.1/6.2), not wired; §7 sync is open — B-3, S3-T2 |
| ssh-config `github-work` alias placement | **Missing as automation** | Hand-edited — B-4 |
| Native user app (wizard + tray, de-mocked) | **Built** (S1–S17 green) | Not packaged/notarized |
| App signing / notarization / self-update (signed) | **Missing (owner-gated)** | Apple cert, notarytool creds, minisign custody — P-7 |
| App first-run: writes manifest / runs `update` | **[VERIFY]** | Unconfirmed; the load-bearing unknown — S2 |
| "Two CLIs" — which binary owns `update`/`layers` | **[VERIFY]** | `cli-copilot` vs `claude-copilot`'s `cc` — S2 |

---

## 7. Open decisions for the owner

- **OD-1 — Bootstrap-cred provisioning method for a new machine.** Build
  `copilot infisical identity provision` and mint a **scoped, per-machine**
  identity (recommended — least privilege, revocable per device), or keep placing
  the org-wide `ecosystem-admin` creds on each machine (fast, but org-wide blast
  radius; gap-analysis flags this High). Decides S3-T1.
- **OD-2 — Who owns onboarding: the user app or the CLI.** Recommend a CLI verb
  (`copilot onboard`) does the compute (manifest write, key gen, provision, sync)
  and the app renders it (invariant #1). Decides D3, S3-T3, and whether S3 is ever
  "one command."
- **OD-3 — Manifest delivery.** Wizard-written vs `copilot init` vs a downloadable
  seed. Must be a *parse/derive-from-`ecosystem.yml`* action, never app-computed.
- **OD-4 — Laptop SSH-key strategy.** Per §7, generate a **new** on-device key on
  the laptop registered under the same GitHub identity (recommended — no private
  key ever leaves a machine), vs. any form of key sync (explicitly open/undesigned).
- **OD-5 — App distribution/signing.** Unblock P-7: Apple Developer ID cert,
  notarytool creds, minisign two-of-N custody, update-feed endpoint. Owner-gated;
  blocks S2-T1 and the whole signed-app path.
- **OD-6 — "Two CLIs" reconciliation.** Confirm and document which binary
  (`cli-copilot`'s `copilot` vs `claude-copilot`'s `cc`) the app shells for
  `update`/`layers`/`doctor`, and whether the content components need a second
  sync path. Fix the docs that disagree (memory `four-programs-two-names`).
- **OD-7 — Codex foundation pin.** `codex-copilot` has no tags, so a Codex-shop
  `foundation-pin` check fails. Not blocking for ENAC (claude shop) but must be
  resolved before any Codex standup — tag `codex-copilot` or special-case it.
- **OD-8 — Gated public flip** (carried from Phase 2 Step F / Phase 4). The
  one-way private→public flip of `knowledge-copilot` + `cli-copilot` stays
  deferred until this install/onboarding proof is green. Not part of this phase's
  work; named so it is not forgotten.

---

## 8. Placement + index updates

This doc: `docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-ecosystem-install-and-onboarding-proof.md`

Index updates made alongside it: the initiative `README.md` Phase Index gains a
**Phase 5** row (org-config migration + cutover — Done) and a **Phase 6** row
(this — "Prove install + two-machine onboarding end-to-end"; depends on Phase 5;
status "hand-off — the next work"), plus Validation-Contract **V-5** ("a cold
laptop onboards and inherits the tier with no hand-copied secret or key").

---

## 9. References

**Initiative & phases**
- `docs/40-initiatives/02-enac-self-onboarding/README.md`
- `…/phases/phase-2-standup-and-rollout.md` (Steps A–F — the standup/fan-out runbook; do not duplicate)
- `…/phases/phase-3-tier-inheritance-and-secrets.md` (what shipped)
- `…/phases/phase-4-tier-completion-handoff.md` (config inheritance, `update`, per-secret routing — code complete)
- Phase 5 (org-config migration + cutover): the `phase-5(…)` commits in `cli-copilot`/`cli-copilot-internal`, WP-79, and session memory `phase-5-org-config-migration`
- `…/decisions/ADR-001/002/003` (one org, `-internal` naming, dogfood ENAC)

**Product & invariants**
- `CLAUDE.md` (repo root — invariants #1 parse-never-compute, #2 single-process, #3 never-destroy, #4 no-weaken, #6 secrets never in inheritance)
- `docs/00-overview/product-brief.md`, `docs/START-HERE.md`

**Admin side**
- `.claude/skills/admin-bootstrap/SKILL.md`; `scripts/admin_bootstrap.sh` (+ `scripts/tests/test_admin_bootstrap.sh`)
- `docs/01-architecture/admin-standup-contract.md`; `docs/06-deployment/admin-prerequisites.md`; `docs/06-deployment/standup-runbook.md`

**User app**
- `native/wizard.swift`, `native/control-tower-tray.swift`, `native/cli-client.swift` (`CliLocator` @ line 51), `native/admin.swift`
- `scripts/build-user.command`, `build-admin.command`, `sign.sh`, `notarize.sh`

**CLI tier install (the critical dependency)**
- `cli-copilot/copilot_cli/main.py` (`update` @ 365), `config/sync.py`, `config/layers.py`, `config/managed_store.py`, `config/secrets_ladder.py`, `config/semver.py`, `config/store_readiness.py`
- `cli-copilot-internal/cli.overlay.yml` (committed `config:` blocks); `~/.config/copilot/copilot.layers.yml` (live manifest, foundation `^0.3.0`)
- `cli-copilot-internal/docs/initiatives/infisical-rollout/05-scoped-identities-handoff.md`, `06-scoped-identities-gap-analysis.md` (`TASK-INF-1..6`, G1–G11), `07-ecosystem-admin-operator-plan.md`
- `docs/05-security/credentials-and-boundary.md` (§1.4 keychain, §1.6 store + ladder, §6 on-device SSH key provisioning, §7 multi-machine key sync — open)

**Session memories**
- `cli-tier-inheritance-live.md` (live wiring + every gotcha; manifest/mirror placed by hand)
- `phase-5-org-config-migration.md` (the cutover — org `.env` emptied, mirror is a git clone, `copilot update` idempotent)
- `native-app-rebuilt.md` (two binaries, wizard/tray de-mocked, S1–S17 green; not packaged)
- `m4-distribution-decisions.md` (crash-only watchdog, self-update, owner-gated signing list)
- `four-programs-two-names.md` (the `cc`/`copilot` naming collision — OD-6)
- `admin-first-live-run-blockers.md` (the `^5.13.0` pin history, `admin:org` scope)

**Live-state probes (2026-07-21, this machine)** — `cli-copilot` & `cli-copilot-internal` both even with `origin/main`; tags `v0.1.0/v0.2.0/v0.3.0` present; keychain holds `INFISICAL_CLIENT_ID`/`_SECRET`; `~/.ssh/config` has a `github-work` alias using a single `id_ed25519`; org mirror is a real git clone at `~/.copilot/mirrors/cli/org-internal/`.
