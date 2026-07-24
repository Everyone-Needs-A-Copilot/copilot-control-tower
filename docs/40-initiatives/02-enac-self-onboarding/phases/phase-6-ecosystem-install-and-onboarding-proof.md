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
(`scripts/admin_bootstrap.sh`, 186/186 tests — Phase 2 plus the Phase 6 repository, OAuth,
personal-handoff, and product-pin gates), the live **base +
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

### Entry-gate update — 2026-07-21

Phase 5 is now evidence-bound in `tc` (Tasks 130–135): the foundation config
tests pass (92), the org-overlay suite passes (25 + 1 skipped), the live mirror
is a clean clone at the source commit with no `.env`, and the two plaintext
secret-bearing Phase 4/5 backups found by the readiness audit were permanently
removed. External service credential rotation remains owner-gated because it
changes live trust state.

Codex Copilot is installed and enabled through Codex's native plugin marketplace
(`codex-copilot@codex-copilot-local`). Release `v0.6.0` is published, the live
development install carries a cache-busted 0.6.0 package, and the public package
passes the official plugin validator plus the full smoke suite (39 tests,
version/parity/routing/eval checks). The content baseline is explicitly pinned
to canonical Claude `main`; the previously captured unmerged initiative-branch
lineage is recorded in the parity attestation rather than silently treated as
the release source.

The false-Healthy seam is closed: when no valid ecosystem `layers.manifest` is
configured, `cc doctor --json` now emits a failing
`ecosystem-layer-manifest` checker and `needs-attention`. The app still calls
one structured CLI and renders its verdict. The machine does not yet have a
valid unified ecosystem manifest, so this is an honest blocking state, not a
completed onboarding proof.

**Readiness determination:** the project is ready to *begin* Phase 6. It is not
ready to claim Phase 6 complete. Phase 6 owns the still-missing product-aware
resolver/materializer, verified executable-content policy, personal-layer
content seeding/materialization, completion of the aggregate `cc onboard`
transaction, signed distribution, and the two-machine cold-start proof. Those
are enumerated below and tracked in `tc` PRD-14.

### Repository-provisioning update — 2026-07-21

The repository authority split is now implemented and compiled into both app
paths. Admin Review writes a `[claude, codex]` brief, runs a read-only inventory
for the Knowledge, CLI, Claude, and Codex organization/department repositories,
renders every result, and requires an explicit **Set up organization** action.
The engine repeats the complete inventory before mutation. Existing private
repositories are reused; only explicit HTTP 404s are created private; public
collisions and unreadable responses stop the run.

User Detect now calls the aggregate `cc onboard --org auto --products ...`
plan and Set Up invokes that same transaction with `--apply`. Personal
repository names are `<component>-copilot-private`; existing private
repositories are reused and only explicit 404s are created private on the
authenticated personal account. The transaction then establishes the device
identity, writes the product-aware manifest, materializes the verified layers,
registers Codex Copilot, and runs doctor. No live repository creation was
performed while developing this path.

This closes the software repository/orchestration gap. Signed/notarized
distribution, published signer trust anchors, and the second-machine proof
remain release/owner operations.

### Workspace-activation update — 2026-07-22

The recurring project experience is now separated from both Admin organization
standup and User person/device enrollment. `cc workspace --all --json` discovers
Git projects only under approved roots/the explicit registry, including new
clones with no Copilot lock. `cc workspace configure` uses a portable
`copilot.project.json`, a remote-stable opaque project id, all-product collision
preflight, additive Claude/Codex setup adapters, and a private machine-local
personal-profile association. A declaration is not installation proof.

The User app decodes this contract. Ready projects remain silent; a private
profile associates without entering the shared repo; and only missing or
unfinished shared setup creates one plain-language action. Existing paths block
before either selected product writes. Codex users get one optional macOS folder
picker during User Setup; non-developers never enumerate repositories. This closes the recurring workspace
activation slice, not the aggregate cold-machine onboarding transaction.

### Implementation update — 2026-07-22

The software-controlled onboarding gaps are now implemented. `cc onboard --org
<org>|auto --products claude,codex --json` is the single plan/apply authority.
It validates the Admin handoff, provisions only confirmed-missing private
rank-10 personal packages, creates a distinct on-device SSH key and registers
only its public half, provisions a path-scoped Infisical machine identity into
Keychain, resolves foundation ranges to exact tags, writes the unified
six-layer manifest atomically, runs mirror/policy/materialization, installs
Codex Copilot through a Codex-native marketplace, and finishes with `doctor`.
Every stage is versioned, resumable, and fail closed.

Admin Setup now carries the non-secret Infisical workspace/environment/path
identifiers and initializes minimal rank-30 organization and rank-20 department
packages. Existing unfamiliar content is held; content-bearing repositories use
the fixed review branch. User Setup calls the aggregate transaction in Detect
and Set Up instead of treating personal repositories and update as unrelated
operations.

Claude and Codex now have separate native roots and target allowlists, with
product included in prune identity. Executable dimensions require a valid Git
commit signature from an explicitly allowed fingerprint. Current public
foundation heads are unsigned, so executable foundation activation correctly
blocks until signed releases and trust anchors are published. That is a release
operation, not missing onboarding code.

---

## 1. The end state we are validating

Three installations, two products, three layers per product, no `.env`,
everything regenerable:

1. **Admin configured (this machine).** `Everyone-Needs-A-Copilot` carries the
   private Claude and Codex `<C>-copilot-internal` repos + branch protection + a matching
   `ecosystem.yml`, the managed secret store (Infisical at
   `secrets.ineedacopilot.com`) holds the org secrets, and the company GitHub
   OAuth App exists (device-flow enabled, client id public).
2. **User app on this machine.** The signed/notarized Control Tower user app is
   installed, supervises `cc`, renders honest `--json` status, and `cc` resolves
   both Claude and Codex via **personal (rank 10) + organization (rank 30) +
   public foundation (rank 40)** with every secret
   resolving through the ladder and **zero secrets in any `.env`**.
3. **User app on the laptop (second machine).** A machine that started with an
   empty keychain and no work SSH key onboards, `copilot update` clones both
   mirrors, and every service resolves from the inherited config + store with no
   hand-copied `.env` — proving the tier is *inheritable*, not *hand-wired*.

**Acceptance for the whole phase:** on the laptop, from a cold start, one
`cc onboard --org Everyone-Needs-A-Copilot --products claude,codex --json`
transaction reports, for each product, `personal (10) -> organization (30) ->
foundation (40)`; doctor is healthy; CLI mirrors are cloned/pulled; store
readiness is ready; and a store-backed service is healthy. No secret or store
config is hand-typed into a file, no SSH private key is copied, and Admin Setup
never receives access to the personal repositories.

---

## 2. Prerequisites — what must be true first

| # | Prerequisite | State today | Source |
|---|---|---|---|
| P-1 | GitHub org `Everyone-Needs-A-Copilot` exists; operator is an Owner. | True (live). | `admin-prerequisites.md` |
| P-2 | `gh` signed in with `repo` + `admin:org` scopes. | True (live token includes both scopes). | Phase 2 Step B; live probe 2026-07-21 |
| P-3 | Company GitHub **OAuth App** (device flow on; client id is public config). | Must be created once at github.com → org → Developer settings → OAuth Apps. | `admin-standup-contract.md §1.6` |
| P-4 | Managed secret store (Infisical) reachable at `secrets.ineedacopilot.com`, org secrets populated. | Live; org secrets in `copilot-ecosystem/prod/shared`. | Phase 3; `05-scoped-identities-handoff.md` |
| P-5 | Public foundation pins resolve. CLI foundation is `^0.3.0`; Claude uses the ratified compatible pin; Codex resolves `v0.6.0`. | True: the Codex 0.6.0 release tag is published and its package/plugin contract is validated. | live probe; Codex release QA WP-107 |
| P-6 | Both CLI repos are **pushed** so a laptop can clone them. | True: `cli-copilot` and `cli-copilot-internal` are both even with `origin/main` (probed). The private org repo is cloned over `ssh-work` per the manifest. | live probe |
| P-7 | App signing/notarization credentials for distribution. | **Partial** — a valid Developer ID Application identity exists, but notary/release credential evidence and a signed/notarized artifact are absent. | `m4-distribution-decisions.md`; live probe 2026-07-21 |

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
  `harness: [claude, codex]`, `departments: []`, `store: connected` (Infisical endpoint,
  the ENAC scope mapping), `github_app.client_id`. *Complexity: Low.*
- **S1-T4 — Dry run then real run.** `bash scripts/admin_bootstrap.sh --verify
  --json --brief <path>` (read-only plan-of-record), review, then
  `bash scripts/admin_bootstrap.sh --brief <path>` (additive/idempotent). Creates
  missing `<C>-copilot-internal` repos, sets branch protection, authors
  `ecosystem.yml` v2.0. *Complexity: Medium.*
- **S1-T5 — Confirm the three known engine fixes** alongside the run (Phase 2
  Step B "Known engine gaps"). They shipped in Control Tower commit `9694b02`:
  the phantom `<org>/copilot-ecosystem` ref, the stale `docs/reference/` paths,
  and packaged resource-path resolution in `native/admin.swift`. Do not rebuild
  them; retain their regression coverage. *Complexity: Low.*
- **S1-T6 — Setup check (verify verb).** Re-run `--verify --json`; confirm a
  clean column of `pass` with `must_fix: 0`. *Complexity: Low.*

### What it provisions

Private `knowledge-copilot-internal` / `cli-copilot-internal` /
`claude-copilot-internal` / `codex-copilot-internal` repos in
`Everyone-Needs-A-Copilot`, branch protection,
`ecosystem.yml` v2.0 (org, harness list, components, departments, store pointer,
`github_app.client_id`, foundation pin), org base permission `read`. It does
**not** provision people, integrations, secrets, or personal repositories —
those live in GitHub team membership, per-repo registries, Infisical, and the
authenticated User Setup stage respectively. It does provision and verify the
non-secret personal-handoff declaration.

### Acceptance

Verify verb returns all-`pass`, `must_fix: 0`; the four `-internal` repos exist
private with branch protection; `ecosystem.yml` parses and matches the brief; the
leak-scan passed before push; `personal-handoff` declares user ownership/rank 10
without identifying a user or repository (invariant #6).

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

### First-run behavior — audited current state

The audit resolved the earlier unknowns:

- The current wizard calls `cc layers join`, but no existing flow constructs the
  unified Claude/Codex/personal manifest required here. This machine's
  `~/.config/copilot/copilot.layers.yml` is a hand-placed, CLI-only two-layer
  manifest, and `cc` has no configured `layers.manifest`.
- The tray polls `cc doctor`; it does not execute the complete content + service
  onboarding transaction on first run. CLI Copilot's mirror-sync remains a
  separate component operation.
- `cc` is now ratified as the single control-plane seam. Phase 6 implements
  `cc onboard` to coordinate product resolution, personal provisioning, and CLI
  mirror sync. Control Tower continues to render one CLI result.

### Acceptance

App launches, tray renders the single `cc` verdict, and the wizard completes the
Admin-to-User handoff. For both Claude and Codex, the structured result shows
`personal (10) -> organization (30) -> foundation (40)`; CLI mirrors are present,
store readiness is ready, a store-backed service is healthy, and no secret is in
an `.env`. The personal repositories are owned by the authenticated user and no
personal content appears in Admin output.

### Decisions

- **D3 (ratified — who owns onboarding).** `cc onboard` owns the transaction and
  coordinates the separately installed CLI/service component. Control Tower
  calls that one verb and renders its result. The app never writes the manifest,
  resolves precedence, or merges health from two CLIs.
- **D4 (ratified — personal authority).** Admin Setup prepares and verifies the
  handoff. User Setup, authenticated as the individual, creates/selects personal
  repositories and writes rank-10 state. Admin never receives personal access.

---

## 5. Step 3 — User app on the laptop (the second-machine test)

**Goal:** a machine that starts with an **empty keychain and no work SSH key**
onboards and inherits the exact same tier. This is the honest test of "install,"
and the development tooling now reduces it to an installer plus one onboarding
transaction. Signed release distribution remains separate. Below is the full
cold-start checklist; each line names who/what must provide it and whether it
exists today.

### 5.1 Cold-start bootstrap checklist

| # | The laptop needs… | Provided by | Exists today? |
|---|---|---|---|
| B-1 | The `cc` control-plane CLI and the `copilot` service CLI installed at supported absolute paths. | The test installer installs immutable compatible commits without relying on bare `cc`; the release app will vendor signed artifacts. | **Development path built** (`scripts/install-test-clis.sh`); signed release artifact remains owner-gated. |
| B-2 | A unified ecosystem manifest for Claude and Codex: personal rank 10, organization rank 30, foundation rank 40. | Derived and written by `cc onboard` from the Admin handoff plus the authenticated user. | **Built and transaction-tested.** Live machine proof remains. |
| B-3 | SSH access to private organization repositories. | A new on-device ed25519 keypair; only its public half is registered with GitHub. | **Built and tested with injected GitHub/SSH seams.** Live laptop proof remains. |
| B-4 | Managed `github-work` and `github-personal` aliases in `~/.ssh/config`. | One bounded Control Tower block; unrelated content is preserved and unmanaged alias collisions hold. | **Built and tested.** |
| B-5 | Scoped Infisical credentials in the laptop Keychain. | `copilot infisical identity provision` creates/reuses a no-org-access identity, exact environment/path read role, membership, universal-auth client, and one-time secret written directly to Keychain. | **Built and tested.** Live Infisical proof remains. |
| B-6 | The store **config** (endpoint, workspace, env, path). | **Inherited** — it travels in the committed `cli.overlay.yml config:` block and `copilot update` clones it into the mirror; `managed_store._find_store_layer` reads it from the composed config, no `.env` needed. | **Done** — config inheritance shipped (Phase 4 #1; verified 3-level). |
| B-7 | `copilot update` to clone both mirrors (never-destroy, semver range → `v0.3.0`). | Built (`config/sync.py`, `main.py:365`). | **Done.** |
| B-8 | The signed user app installed (optional for the CLI proof, required for the product). | S2 pipeline (blocked on P-7). | **Blocked** on signing/notarization. |

### 5.2 The one-command target vs. today's manual steps

**Today:** install the two CLIs from source or a development checkout (B-1),
then run the one aggregate onboarding command. Manifest, SSH, personal package,
store identity, mirror sync, materialization, Codex plugin install, and doctor
are no longer manual steps.

```bash
# Read-only collision/install plan first.
./scripts/install-test-clis.sh --json

# Apply only after the plan is unblocked. Existing unrelated cc/copilot paths
# are held, never replaced.
./scripts/install-test-clis.sh --apply --json

# Read-only ecosystem plan, then the explicit setup action.
~/.local/bin/cc onboard --org auto --products claude,codex --json
~/.local/bin/cc onboard --org auto --products claude,codex --apply --json
```

Before the pinned commits are published, a local checkout can exercise the
same immutable installer by setting `ENAC_CLAUDE_REPO` and `ENAC_CLI_REPO` to
those checkout paths. The requested commit hashes are still verified exactly;
the override changes transport, not provenance.

**The one-command target:** `cc onboard --org Everyone-Needs-A-Copilot
--products claude,codex --json` (also invoked by the app wizard) that: consumes
the Admin handoff, creates/selects user-owned personal repositories, writes the
product-aware manifest,
writes the ssh-config alias, generates + registers the on-device SSH key via the
GitHub device flow (§6.1/§6.2 machinery), drives `copilot infisical identity
provision` to mint a **scoped per-machine** identity and drop its creds in the
laptop keychain, resolves/materializes Claude and Codex, coordinates `copilot
update`, and prints one verify summary. **This orchestration is implemented.**
The remaining cold-machine bootstrap gap is distributing pinned signed CLI/app
artifacts rather than installing the CLIs from source.

### 5.3 Tasks to close the laptop gap

- **S3-T0 — COMPLETE: Make ecosystem resolution product-aware.** Validate ranks per
  product; resolve winners by `(product, dimension, item)`; materialize only to
  allowlisted Claude/Codex roots; and implement real fail-closed signature/policy
  verification for executable content. Same-named skills must coexist across
  products. *Unit + integration tests required. Complexity: High.*
- **S3-T1 — COMPLETE: Build `copilot infisical identity provision`** (gap-analysis
  `TASK-INF-1`+`TASK-INF-2`): scoped project role (path-scoped CASL DSL, proven
  with the disposable allow/deny test `TASK-INF-3`), universal-auth attach,
  one-time client-secret mint, `--write-env`/keychain-write with redaction. *Unit
  + integration tests required.* *Complexity: High.*
- **S3-T2 — COMPLETE: Wire on-device SSH key generation at onboarding** (`credentials-and-
  boundary.md §6.1`): ed25519 keypair generated on the laptop, private half into
  keychain-backed `ssh-agent` (`ssh-add --apple-use-keychain`), public half
  registered via the GitHub device flow (§6.2). Follow §7's "own keypair per
  machine, same identity" — no key sync. *Unit + integration tests required.*
  *Complexity: High.*
- **S3-T3 — COMPLETE: Build `cc onboard` + the rendered wizard step.** Consume the Admin
  handoff; create/select the authenticated user's Claude and Codex personal
  repositories; seed rank 10; write the product-aware manifest; write the SSH
  alias; sequence S3-T0/S3-T1/S3-T2 and CLI mirror update; return opaque personal
  provenance and complete doctor evidence. *Unit + integration + UI E2E tests
  required. Complexity: High.*
- **S3-T4 — DEVELOPMENT COMPLETE; SIGNED ARTIFACT OWNER-GATED: Package a laptop CLI installer** (pipx/uv one-liner or the app bundles
  + installs the CLI on first run). *Complexity: Medium.*
- **S3-T5 — Cold-machine acceptance run** on the real laptop with an empty
  keychain. *Complexity: Medium.*

### Acceptance

On the laptop, from cold, `cc onboard ... --json` reports for both Claude and
Codex: `personal (10) -> organization (30) -> foundation (40)`, all effective
items have product-correct provenance, and doctor is healthy. CLI mirrors are
cloned, store readiness is ready, and a store-backed service is healthy. The
laptop's own SSH key is registered; personal repositories belong to the user;
and there is **no `.env`, hand-copied secret, copied SSH private key, or personal
content in Admin output**.

---

## 6. What's already built vs. missing

| Piece | Status | Gap |
|---|---|---|
| Public/private foundation split, pushed | **Built** | — |
| GitHub standup engine (`admin_bootstrap.sh`), plan/apply/verify verbs | **Built** (186/186 offline assertions) | App renders the repository plan and invokes apply directly; the development app packages the engine and its pinned tools. |
| `ecosystem.yml` v2.0 authorship | **Built** (engine step 5) | Public OAuth client id, product-specific Claude/Codex pins, and the non-secret personal handoff are emitted and verified; live-org proof remains in S4. |
| Tier runtime (base + overlay, nearest-wins) | **Built + live** | — |
| Credential ladder (store → keychain → device-flow stub → paste) | **Built + live** | Rung 3 device-flow is a clean stub (unbuilt) |
| Config inheritance (committed `config:` blocks, no `.env`) | **Built + live** (Phase 4 #1) | — |
| `copilot update` mirror-sync (never-destroy, semver, `--json`) | **Built + live** | — |
| Secrets in Infisical + keychain, `.env` emptied | **Built + live** (Phase 5 cutover, 2026-07-21) | — |
| Codex public foundation package | **Built + published** | `v0.6.0`; official plugin validation + smoke suite pass; live cache-busted install enabled |
| Claude/Codex product-aware resolver | **Built; QA slice green** | Resolution identity is `(product, dimension, item)`; ranks are unique/ordered per product, layer ids are globally unique, and same-named Claude/Codex items coexist. |
| Product-specific materialization | **Built; focused QA green** | Claude/Codex native roots, target allowlists, product-scoped prune identity, and cross-product denial are implemented. |
| Executable-content signature/policy verification | **Built; focused QA green** | Valid Git signature + exact allowed fingerprint required. Current unsigned public heads are a release gate. |
| Personal layer provisioning | **Built; focused QA green** | Explicit 404-only private creation, confirmed-empty rank-10 seed, unfamiliar-content hold, and idempotent reuse. |
| Unified manifest delivery to a new machine | **Built; transaction-tested** | Aggregate onboarding writes and configures the six-layer manifest atomically. Live proof remains. |
| CLI install on a new machine | **Development installer built** | Immutable source commits, plan/apply, collision hold. Signed vendored release artifact remains owner-gated. |
| Machine-identity bootstrap-cred provisioning | **Built; 58 focused Infisical tests green** | Live scoped-identity proof remains. |
| On-device SSH key gen + GitHub registration at onboarding | **Built; focused QA green** | Live second-machine proof remains. |
| ssh-config managed aliases | **Built; focused QA green** | Surgical bounded block; collisions hold. |
| Native user app (wizard + tray, de-mocked) | **Built** (S1–S17 green) | Not packaged/notarized |
| App signing / notarization / self-update (signed) | **Missing (owner-gated)** | Apple cert, notarytool creds, minisign custody — P-7 |
| App first-run orchestration | **Built; Swift builds and smoke contracts green** | Detect plans and Set Up applies the one aggregate transaction. |
| Recurring workspace activation | **Built; QA approved** | `TASK-149`–`TASK-152`; bounded discovery, root approval, portable declaration + ownership lock, opaque personal association, portable two-product additive setup, and User-app prompt are implemented (WP-124–WP-136). Cold-machine foundations and personal-repository hydration remain in aggregate onboarding. |
| "Two CLIs" ownership | **Ratified** | `cc` is the control plane and coordinates `copilot`; app calls only `cc` |

---

## 7. Ratified decisions and remaining owner gates

- **RD-1 — Bootstrap credentials.** Use a scoped, revocable per-machine identity;
  do not distribute the org-wide `ecosystem-admin` credential. The provisioning
  verb is implemented; live service proof remains owner-controlled.
- **RD-2 — Onboarding authority.** `cc onboard` computes and mutates; Control
  Tower renders one structured result.
- **RD-3 — Manifest delivery.** `cc onboard` derives the manifest from the Admin
  handoff and authenticated user choices. The app does not author YAML.
- **RD-4 — Personal boundary.** Admin provisions organization; User Setup creates
  or selects user-owned personal repositories. Admin sees opaque health only.
- **RD-5 — Laptop SSH keys.** Generate a new on-device key for each machine under
  the same GitHub identity. Never sync private keys.
- **RD-6 — Product isolation.** Resolve by `(product, dimension, item)` and
  materialize only to per-product allowlisted targets.
- **OG-1 — App distribution/signing.** Unblock P-7: Apple Developer ID cert,
  notarytool creds, minisign two-of-N custody, update-feed endpoint. Owner-gated;
  blocks S2-T1 and the whole signed-app path.
- **OG-2 — Company GitHub OAuth App.** An org owner must create it in GitHub's web
  UI with device flow enabled and supply the public client id; no supported API
  creates this app on the owner's behalf.
- **OG-3 — Gated public flip** (carried from Phase 2 Step F / Phase 4). The
  one-way private→public flip of `knowledge-copilot` + `cli-copilot` stays
  deferred until this install/onboarding proof is green. Not part of this phase's
  work; named so it is not forgotten.

---

## 8. Execution plan — software completion through two-machine proof

This is the durable execution order approved on 2026-07-22. Live status,
dependencies, QA metadata, and work products remain authoritative in `tc`
PRD-14; this section records the delivery sequence and completion contract.

### A. Complete the shared Codex organization layer (`TASK-144`) — implemented

1. Define the loadable `codex-copilot-internal` package shape and its signed
   organization manifest.
2. Make Admin Setup seed only a confirmed-missing/empty private repository;
   reuse existing private content without overwriting it.
3. Extend Admin verify so an existing repository is not considered ready until
   its manifest, package content, policy, foundation pin, and branch protection
   are valid.
4. Prove the organization package installs above Codex foundation `v0.6.0`
   without changing the public foundation or exposing organization content.

### B. Complete personal layers and product isolation (`TASK-145`) — implemented

1. Change manifest validation and resolution identity from
   `(dimension, item)` to `(product, dimension, item)`. Rank uniqueness and
   ordering are enforced inside each product stack, so Claude rank 10 and Codex
   rank 10 may coexist while duplicate ranks within one product fail closed.
2. Define allowlisted Claude and Codex materialization targets. A product may
   never write to the other product's target roots.
3. After User Setup reuses or creates each private personal repository, seed a
   minimal rank-10 package only when the repository has no user content. Never
   replace an existing manifest or infer that an unfamiliar repository is safe
   to initialize.
4. Return content-free provenance and health. Personal names, paths, and file
   contents must not enter Admin output, telemetry, or shared repositories.
5. Prove a second run is idempotent and a dirty/user-owned target is held rather
   than overwritten or pruned.

### C. Build the aggregate cold-machine transaction (`TASK-146`) — implemented

The recurring workspace slice (`TASK-149`–`TASK-152`) is an input to this work,
not a substitute for it. It assumes installed public foundations and an enrolled
person/device; the aggregate transaction must establish those prerequisites on
a cold machine before workspace activation can become invisible.

1. Add resumable stages to `cc onboard --org <org> --products
   claude,codex --json`: authenticate; consume the signed Admin handoff;
   inventory/apply personal repositories; establish the machine's GitHub SSH
   identity; provision its scoped store identity; write the unified manifest;
   sync mirrors; resolve; materialize; and run doctor.
2. Add supported, pinned installation of `cc` and `copilot` for a machine that
   has neither tool. Resolve binaries by absolute path and never rely on bare
   `cc` during compilation.
3. Generate a distinct on-device SSH key and surgical `github-work` host block;
   register only the public key. Never copy another machine's private key.
4. Provision a scoped, revocable per-machine Infisical identity into the OS
   keychain. Never reuse the organization-wide administrator identity as the
   user bootstrap credential.
5. Have Control Tower invoke and render this one structured transaction. The
   app must not author manifests, resolve precedence, merge CLI health, or
   weaken a failed stage.

Every mutating stage repeats its read-only preflight, reports `planned`,
`applied`, `reused`, `held`, or `blocked`, and is safe to resume after a partial
failure. Already-passing stages remain intact.

### C.1 Adopt existing ecosystems instead of requiring reset (`TASK-155`) — implemented

1. Aggregate onboarding inventories personal repositories and the local layer
   manifest before the first mutation and returns structured `reuse`, `create`,
   `migrate`, `repair`, or `review` actions.
2. The supported predecessor manifest (`component:`) is translated
   deterministically to `product:`. Existing products outside Claude/Codex,
   including the live CLI stack, are retained in the merged manifest.
3. Repair and migration keep a content-addressed rollback copy. Unfamiliar or
   conflicting manifests stop the complete Apply before personal repository,
   SSH, store, or local-manifest mutation.
4. Admin and User apps render the plan in plain language. Admin applies the
   same adopt-in-place policy to organization/department repositories; User
   Setup renders local/personal decisions and the recurring project flow keeps
   existing per-project setup.
5. Focused contract tests cover retained legacy layers, reversible migration,
   and a zero-write unfamiliar-manifest hold. The remaining proof is the live
   Admin-machine and laptop execution in section E.

### D. Produce the release candidate and close owner-controlled gates

1. Supply the organization GitHub OAuth App client id with device flow enabled.
2. Supply Developer ID/notary credentials and settle minisign/update-feed key
   custody.
3. Build pinned CLI artifacts plus the user and Admin applications; sign,
   notarize, staple, checksum, and verify them from a clean install location.
4. Keep every unavailable credential or external authorization as an explicit
   blocker. No development key, administrator credential, hand-authored YAML,
   or bypass flag may be substituted to manufacture a green result.

### E. Execute the proof in the only safe order (`TASK-147`)

1. On this machine, run Admin Setup for `Everyone-Needs-A-Copilot` with
   `harness: [claude, codex]` and no departments. Review the plan before apply,
   then require four private organization repositories and `must_fix: 0`.
2. In a fresh local macOS user account, install the release candidate and run
   User Setup. Require both three-layer stacks, valid provenance, ready store,
   healthy doctor, idempotence, and a demonstrated dirty-file hold.
3. Only after steps 1–2 pass, reset the laptop's Copilot-owned local state using
   the separately reviewed quarantine-first reset procedure. Do not delete the
   public, organization, or personal remote repositories; an existing private
   personal repository is a valid reuse-path proof.
4. Install the same signed release on the laptop and repeat User Setup with a
   newly generated laptop SSH key and laptop-scoped store identity.
5. Store redacted evidence for both machines against `TASK-147`. Phase 6 closes
   only when the clean laptop reaches the acceptance state in §1 without a
   copied secret, copied private key, `.env`, or hand-written manifest.

The laptop is deliberately not reset before a signed replacement path passes
on this machine. Erasing the current environment earlier would create a clean
machine without a supported way back and would not constitute onboarding
evidence.

---

## 9. Placement + index updates

This doc: `docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-ecosystem-install-and-onboarding-proof.md`

Index updates made alongside it: the initiative `README.md` Phase Index gains a
**Phase 5** row (org-config migration + cutover — Done) and a **Phase 6** row
(this — "Prove install + two-machine onboarding end-to-end"; depends on Phase 5;
status "hand-off — the next work"), plus Validation-Contract **V-5** ("a cold
laptop onboards and inherits the tier with no hand-copied secret or key").

---

## 10. References

**Initiative & phases**
- `docs/40-initiatives/02-enac-self-onboarding/README.md`
- `…/phases/phase-2-standup-and-rollout.md` (Steps A–F — the standup/fan-out runbook; do not duplicate)
- `…/phases/phase-3-tier-inheritance-and-secrets.md` (what shipped)
- `…/phases/phase-4-tier-completion-handoff.md` (config inheritance, `update`, per-secret routing — code complete)
- Phase 5 (org-config migration + cutover): the `phase-5(…)` commits in `cli-copilot`/`cli-copilot-internal`, WP-79, and session memory `phase-5-org-config-migration`
- `…/decisions/ADR-001/002/003/004` (one org, `-internal` naming, dogfood ENAC,
  Admin-shared/User-personal authority)

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
- `four-programs-two-names.md` (the `cc`/`copilot` naming collision — resolved by
  RD-2: `cc` is the control plane)
- `admin-first-live-run-blockers.md` (the `^5.13.0` pin history, `admin:org` scope)

**Live-state probes (2026-07-21, this machine)** — `cli-copilot` &
`cli-copilot-internal` both even with `origin/main`; CLI tags
`v0.1.0/v0.2.0/v0.3.0` and Codex tag `v0.6.0` are present; Codex's live plugin is
enabled; keychain holds `INFISICAL_CLIENT_ID`/`_SECRET`; `~/.ssh/config` has a
`github-work` alias using a single `id_ed25519`; org mirror is a real git clone at
`~/.copilot/mirrors/cli/org-internal/`; `cc doctor --json` honestly reports
`needs-attention` because no unified `layers.manifest` is configured.
