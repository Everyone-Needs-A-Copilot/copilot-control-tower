# Service Blueprint

<!--
FACILITATION GUIDE — Service Designer
======================================
The service blueprint maps the full system — not just what the user
sees, but what happens behind the scenes to make the experience work.

PREREQUISITE: Journey maps must be completed.

CONVERSATION FLOW:
1. Map customer actions (what the user does)
2. Map frontstage (what the user sees and interacts with)
3. Map backstage (what happens behind the scenes)
4. Map support processes (systems and infrastructure)
5. Identify pain points and opportunities in each layer

QUESTIONS TO ASK:

## Round 1: Customer Actions
- "Walk me through every action the user takes, from first
  login to completing their primary task."
- "What decisions does the user make at each step?"
- "Where does the user need to provide input vs. where does
  the system work autonomously?"

## Round 2: Frontstage
- "What does the user see at each step? What's on their screen?"
- "How does the product communicate what it's doing?"
- "Where are the waiting moments? What does the user see while
  the system is working?"

## Round 3: Backstage
- "What happens behind the scenes at each step?"
- "What processing, computation, or AI work runs invisibly?"
- "What data is being created, transformed, or consumed?"

## Round 4: Support Processes
- "What external systems does this depend on?"
- "What data stores are needed?"
- "What third-party APIs are involved?"
- "What monitoring and alerting is needed?"

## Round 5: Pain Points & Opportunities
- "Where in this blueprint are the highest-risk areas?"
- "Where could the system fail silently?"
- "Where are the biggest opportunities to delight the user?"

SYNTHESIS:
Present as a layered blueprint showing all four layers aligned
to the same timeline/journey. Highlight failure points and
dependencies.
-->

> **STATUS — rebuilt from evidence 2026-08-02. Describes Copilot Control Tower v0.4.0** (build 19, embedded helper `cc 2.2.0`, notarized arm64 DMG). This replaces a version written 2026-07-17 whose MDM/fleet framing, Rust/Tauri backstage, and telemetry lane no longer describe anything that ships. Every stage, surface, verb, and failure below is read from the shipping code, the released artifacts, the CLI contract, or dated incident evidence in this repository.

---

## The architectural fact this whole blueprint rests on

**Control Tower parses. It never computes.** Every verdict a person reads on screen — this layer is current, this project needs guided setup, this connection is ready, your organization has 20 declared services and three of them are missing credentials — was computed by the `cc` / `copilot` CLI and rendered by the app without judgment added. The app holds no resolution, sync, merge, signature, entitlement, or health logic of its own.

The consequence, stated as a design test rather than a slogan: **if Control Tower vanished from a machine, the CLI would still be correct.** Nothing about the ecosystem's state, safety, or truth depends on the app being installed. The app is a face and a supervisor over a pipeline that is already right without it. The moment that stops being true, the product has failed — this is `CLAUDE.md` invariant #1 and `SOUL.md` Principle 1, and it is the reason the backstage section of this blueprint is longer than the frontstage one.

A concrete illustration shipped in v0.4.0. The wizard's new step 6, "Your connections," renders the organization's full declared service roster with each row's real credential readiness. The app filters on exactly one field — the CLI-computed `secret_state` (`ready` | `needs-connect` | `no-store`) — and never inspects a secret value, never contacts the secret store, and never derives readiness itself. An unrecognized future `secret_state` value is grouped with `no-store`, never with `ready`. That is invariant #1 working exactly as designed, in a feature that could very easily have been built the other way.

---

## Provenance and evidence stamps

Grounded in: `native/*.swift` (the ~22,650-line shipping app), `scripts/admin_bootstrap.sh`, `docs/01-architecture/cli-contract.md`, `docs/01-architecture/inheritance-and-publish.md`, `docs/01-architecture/schemas/` (15 JSON Schemas), `docs/05-security/credentials-and-boundary.md`, `docs/10-reference/cse-alignment-decisions.md` (D1–D10), ADR-001 … ADR-008 (all Accepted), `CHANGELOG.md`, the retained signed releases under `release/`, and two bodies of incident evidence: `docs/40-initiatives/03-schema-mismatch/` (complete) and `docs/40-initiatives/02-enac-self-onboarding/phases/phase-7-live-run-evidence-stage-a.md` (the live run, Stages A → E).

Stamps used below: **SHIPPED** (in the v0.4.0 binary or its release pipeline) · **PROVEN** (exercised in a live run with recorded evidence) · **HYPOTHESIS** (designed, never validated with a real actor) · **DEFERRED** (formally not built, per an Accepted ADR) · **OPEN** (a named, unresolved gap).

---

## Actors and lanes

This service does not have one user and one journey. It has four actors on four lanes that touch at exactly three handoff points, and the handoffs are where it breaks.

| Actor | Lane | Surface | Evidence stamp |
|---|---|---|---|
| **The person** (the non-technical consumer — the product's reason to exist) | Adopt → run → keep running | `Copilot Control Tower.app`: 9-stage wizard, menu-bar tray, Settings | SHIPPED; **HYPOTHESIS as an experience** — no independent non-technical person has completed it |
| **The organization's admin** (the enabler) | Stand up the org, then govern it | `Copilot Control Tower Admin.app`: 16 surfaces over a deterministic bash engine | SHIPPED; **PROVEN once, by the owner**; HYPOTHESIS for an independent operator |
| **The author** (a trained early-adopter who writes org/department content) | Author → publish → let cadence carry it | No app surface. A markdown editor, then a human-invoked `git push` into the tier repo | **DEFERRED** (`cc publish`, ADR-008) with a documented manual substitute; never run with more than one writer |
| **The publisher** (owner-only) | Build → sign → notarize → release | `Publisher Setup.app` + `scripts/package-user-release.sh` | SHIPPED; PROVEN across eight version lines |

The publisher lane is not a customer journey, but it is unquestionably part of this service: the person's very first frontstage moment — a DMG that opens without Gatekeeper stopping them — is manufactured entirely in that lane. A blueprint that omitted it would omit the origin of the product's single most fragile dependency, the pinned vendored helper.

---

## Blueprint spine — the real stages

These stages come from the shipping surfaces, not from a template. They are deliberately **not** a linear Awareness → Consideration → Purchase → Use → Support arc; this service is a loop with two re-entry points and one lane that never converges.

```
                    ┌──────────────────────── H1 ────────────────────────┐
                    │  handoff: ecosystem.yml + GitHub team membership   │
                    ▼                                                    │
  S0 ORG STANDUP ──────────► S1 GET IT ──► S2 FIRST RUN ──► S3 STEADY STATE
   (admin, 11 surfaces)      (download,    (9-stage        (tray, 300 s poll,
                              DMG, first    wizard)         12 badges, silence)
                              open)              │                │    ▲
                                                 └──── H2 ────────┘    │
                                              handoff: Verify → poll   │
                                                                       │
        S4 CHANGE LANDS ◄──────────────────────────────────────────────┤
        (Sync now · What changed · Join a department · fanout)         │
                                                                       │
        S5 SOMETHING IS WRONG ◄────────────────────────────────────────┤
        (holding states H1–H7 · project triage · diagnose · rollback)  │
                │                                                      │
                └──────── recovery, or ────────────────────────────────┘
                          escalation to the admin

  S6 GOVERNANCE (admin, 5 surfaces) ── add a department · someone left ·
                                        connect the store · org setup

  ── LANE B (author) ────────────────────────────────────────────────────
  edit in a markdown editor → commit → human-invoked push to the tier repo
  → every consuming machine picks it up on its next pull.  No app surface.
  DEFERRED as a product verb; documented as a manual procedure.

  ── LANE C (publisher, owner-only) ─────────────────────────────────────
  build → sign → verify vendored cc → headless detect → headless setup
  transaction → notarize → staple → Gatekeeper → DMG → release/
```

**S3 is the destination, and its content is silence.** The success state of this product is a menu-bar glyph with no badge on it. Everything else in the blueprint exists to reach that silence honestly, or to break it truthfully when it can no longer be earned.

---

## Customer Actions

*What each actor actually does. Autonomous system work is deliberately excluded here and appears in Backstage.*

| Stage | The person | The admin | The author | The publisher |
|---|---|---|---|---|
| **S0 Org standup** | — | Reads the orientation; supplies contacts; connects GitHub; describes the organization in plain language; reads the integrations explainer; connects a shared secret store **or explicitly defers it**; reviews exactly which repositories and teams will be created; hands the brief to Claude Code to execute; runs Setup check | — | — |
| **S1 Get it** | Downloads the signed DMG from the org's deployable download page; drags to Applications; opens it | Distributes the admin build through a private GitHub release, never the public page | — | Cuts and publishes the release |
| **S2 First run** | Reads Welcome; **connects GitHub** (device flow, first real action); waits through Detect; reads what they're getting; picks any department they are entitled to; reviews their connections; reviews their projects; presses **Set up**; watches Verify | Watches nothing — there is no fleet dashboard. Learns of a stuck person only if that person asks | — | — |
| **S3 Steady state** | Glances at the glyph. Usually does nothing. This is the whole intent | — | — | — |
| **S4 Change lands** | Optionally presses `Sync now`; optionally opens `What changed`; optionally joins a newly-entitled department; optionally brings projects up to date | Adds a department when the org grows | Edits content, commits, pushes to the tier repo | — |
| **S5 Something is wrong** | Reads one plain sentence naming what is wrong; takes at most one action that is genuinely theirs — sign in again, grant one GitHub permission, review their own uncommitted work, choose a folder, or copy a diagnostic report / owner handoff to send onward | Receives the escalation; resolves it in GitHub or the store | — | Supersedes a defective build with a new version; the person reinstalls the prior signed DMG |
| **S6 Governance** | — | Adds a department; handles a leaver by removing GitHub team membership and rotating the store tokens their teams could read; connects the shared store later if deferred; reads the org-setup summary | — | — |

**Two rules govern this table, and both are `SOUL.md` case law rather than preference.** The person is asked *only* about their own data and only when the decision is non-deferrable and theirs to make — never to approve a held update, never to unblock a gated one, never to judge something they have no basis to judge. And the person is never shown raw Git: a collaborative conflict must resolve invisibly or hold safely and escalate, and a VCS error dumped on a non-technical person is a named anti-pattern.

---

## Frontstage (Line of Visibility)

### S0 — Org standup: the Admin app, 16 surfaces

Two stage families in one sidebar. **Onboarding (11):** Orientation · Prerequisites · Contacts · Connect GitHub · Describe your organization · Integrations · Secret store · Review setup · Organization setup · Setup check · Done. **Governance (5):** Add a department · Someone left · Connect the shared store · Org setup · Analytics.

The register is orientation-before-input: each surface teaches before it collects. Review setup enumerates the exact repository and team names that will exist. The Integrations surface deliberately ends at "nothing to configure here today" — integrations are built later, in department repos, by an engineer assigned to that department; the admin never declares them. Analytics exists as a governance surface with a toggle and **no emitter behind it** — there is no telemetry in the shipping app at all. This is a frontstage element with no backstage, and it is flagged as such rather than described as working.

### S1 — Get it

A deployable download page that ships with the product so an organization can host and customize its own (swap the videos, the name, the contact). A signed, notarized, stapled arm64 DMG, roughly 24–25 MB. The admin build is never on that page.

### S2 — First run: the 9-stage wizard

`Welcome → Connect GitHub → Detect → What you're getting → Departments → Your connections → Your projects → Set up → Verify`.

Three properties of this surface are worth stating because each was a decision, not a default. **Progress is named, never estimated** — the wizard shows the phase it is in and never a countdown, a percentage, or an ETA, because an estimate is a computed promise the app cannot honestly keep. **The person does not choose components** — everyone gets Knowledge Copilot, CLI Copilot, and the organization's harness Copilot, with a single optional checkbox to add the other harness if they personally use it; "choose your copilots" was replaced by "here's what you're getting." And **the emotional register is flat by design with exactly three sanctioned peaks**, of which the Done send-off — "You have the tools. Now go change the world!" — is an explicit owner override.

Step 6, "Your connections," is new in v0.4.0 and closes what was previously an empty state. It renders the organization's full declared service roster (20 services in ENAC's live configuration) grouped into **Ready to use** and **Available to connect**, with a quiet sentence per unready row naming exactly which credential *names* are missing from the organization's store — never a value, never the words "tier," "mode," or "scope." When the organization's inherited config has not materialized yet, the roster still renders in full with every store-dependent row honestly marked as having no store, rather than collapsing to an empty list.

Step 7, "Your projects," renders five project categories — Ready · Can finish automatically · Needs guided setup · Needs the project owner · Couldn't confirm. **All five classifications are authored by the CLI.** The app filters rows; it never classifies one. "Couldn't confirm" is a first-class, non-embarrassed state.

### S3 — Steady state: the tray

One `NSStatusItem` carrying the aviator-sunglasses glyph, template-tinted, with **no SF-Symbol fallback permitted** — the mark is the mark. Over it sits one of a **closed 12-token badge vocabulary**: `pass · ring · key · update · triangle · wrench · clock · cloud-slash · bang · spinner · hollow · none`. Shape carries the state first and colour second, so the status survives a monochrome render and a colour-blind reader. `none` — draw nothing — is the success state.

Right-click gives `Sync now · What changed · Settings… · Quit` (plus `Open Administration…`, compiled in only in the admin build). The popover reads in the organization's own plain nouns: **YOUR COPILOTS · AVAILABLE TO JOIN** (with a per-row `Join`) **· SHARED WITH YOUR TEAM · YOUR ACCOUNTS**. The one-line status sentence names the failing host — "Codex needs sign-in; Claude is fine" — never a blended "something needs your attention."

`What changed` is a short **Recently** list grouped into "Projects set up for you" and "Projects brought up to date," with an explicit and unapologetic empty state: "Nothing has changed since you last looked."

### S3 — Settings

Four components × four tiers: **Knowledge Copilot · CLI Copilot · Claude Copilot · Codex Copilot**, each expandable across **foundation · organization · department · personal**, every cell in one of five honest states — ready · needs setup · needs attention · not joined · couldn't check. The derivation is pure and shared with the tray, computed once from the CLI's own `doctor`, `onboard`, and `layers` reports. Ranks, manifests, and package states — the real internal vocabulary — never reach this screen.

### S5 — When it is wrong

A named copy family (H1–H7) covers every honest holding state. The specific affordances, all shipping: `Review your changes` when a dirty working tree holds a sync; `Grant this on GitHub` for the one least-privilege permission upgrade; `Choose folder…` / `Not on this Mac` / `Stop watching this folder` for project-root approval; `Finish safely`; `Diagnose in Codex` / `Diagnose in Claude Code`, which open a real Terminal session with a prepared prompt; `Copy diagnostic report`; `Copy project-owner handoff`; `Check again`.

That last cluster is the most interesting frontstage decision in the product. When the app cannot fix something, it does not apologize and stop — it hands the person a way to put the problem in front of an AI assistant that *can* reason about it, or a way to hand it to whoever owns the project. The recovery path is a handoff, not a dead end.

---

## The transitions — where this service actually breaks

Stages are easy. The joints between them are where experience is lost, and this service has three that carry real weight.

### H1 — Admin "Done" → the person's "Welcome"

**What crosses:** exactly two things. An `ecosystem.yml` file committed to the organization's instruction-layer repository — the org's config-of-record that every user's CLI reads — and **GitHub team membership**, which is the entitlement spine in its entirety (D3). Nothing else travels. No profile, no enrolment, no push, no MDM: that mechanism was dropped completely.

**What can break here, and does.** If `ecosystem.yml` has not materialized on the person's machine, `cc connections` returns `org-config-unavailable`. The designed behaviour is not an error screen and not an empty list: the full roster renders with every store-dependent row honestly marked as having no store. If the organization's GitHub OAuth App was never created during standup — it is per-company by ratified decision, never foundation-provided — the person's Connect GitHub step has no client ID to use. If the shared secret store was deferred at standup, every integration row reads `no-store` forever until someone returns to the Connect-the-store governance surface.

**The design property that makes this joint survivable:** each of those three is a *renderable state*, not a crash. The app was built so that an incomplete handoff produces an honest sentence about who owns the missing piece, not a blank screen.

### H2 — Wizard "Verify" → tray steady state

**What crosses:** the person stops being an active participant and becomes a supervised one. The wizard's named, visible, phase-by-phase progress gives way to a 300-second poll and a glyph that will usually say nothing at all.

**Why this joint is fragile:** it inverts the feedback contract without announcing it. During Set up the person is told constantly what is happening; one second after Verify, correct behaviour is total silence — and silence is exactly what a change-averse person reads as "did it actually work?" The mitigations that ship are the returning-person ecosystem view, the persistent Settings matrix that answers "is it all still there" on demand, and `What changed` with its explicit nothing-has-changed state. **This remains the least-validated joint in the product**, because validating it requires watching a real non-technical person cross it, which has not happened.

### H3 — The person's failure → the admin's queue

**What crosses:** a copied diagnostic report or owner handoff, carried by the person, through whatever channel their organization already uses.

**What is deliberately absent:** any fleet dashboard, telemetry, or automatic escalation. When MDM was dropped, the fleet-observability centre of gravity went with it. The admin does not learn that someone is stuck unless that person says so.

**This is a live design tension, not a solved problem.** It is defensible for a small, trusted organization and it keeps the audit surface small. It is also the single largest scaling risk in the service model, and it should be named as such rather than smoothed over.

---

## Backstage

*The line of visibility is drawn immediately below everything above. Everything from here down is invisible to every actor, and it is where nearly every failure in this product's recorded history originated.*

### B1 — The verb seam: what the app is allowed to say to the CLI

The app's entire vocabulary is the following argv set, every call `--json`. This is the complete list; there is nothing else.

| Verb | Purpose in the service | Where it surfaces |
|---|---|---|
| `doctor --json` | The health verdict, per checker, with `severity` (`pass`/`warn`/`fail`) and a closed `layer_role` | Tray badge, Settings matrix, status sentence |
| `auth status` / `auth login` / `auth grant` | GitHub device-flow sign-in; least-privilege upgrade requesting only `write:public_key` | Wizard step 2, `Grant this on GitHub` |
| `layers` / `layers join <id>` | Discover which department/org layers the account is **entitled** to and which are already joined; join one | Wizard step 5, `AVAILABLE TO JOIN` |
| `freshness` / `freshness --all-projects` | The cheap poll target — a single lock SHA comparison, not a full update | The 300 s poll |
| `update` / `update --fanout` / `update --project <p>` | Apply, or report `held` / `blocked` / `offline` | `Sync now`, project rows |
| `onboard --scope personal …` / `onboard --org … --products …` | The whole setup transaction, plan and apply | Detect, Set up, Verify |
| `workspace` (9 subverbs: status, verify, plan, configure, approve-root, forget-root, roots, decline, revert) | Project discovery, classification, and aftercare | Wizard step 7, project drill-in |
| `connections` | The declared service roster with per-row `secret_state` | Wizard step 6, Settings connections card |

**Four verbs are never called by the app**, and the absence is the design. `resolve` and `deprovision` have schemas and retired Rust implementations but no Swift caller. `repair` and `publish` are **formally deferred by ADR-008**: history remediation lives inside `onboard`'s own routing, and the author-side push path is preserved as design record only. No document in this repository may list either as an existing verb.

### B2 — The schema gate: the app's fail-closed front door

Before trusting any field of any CLI response, the app decodes **only** `schema_version` and requires an exact major match — **per verb**. `onboard` requires major **2**; every other verb requires major **1**. The compatibility pin (`controltower.compat.json`, mirrored into every release directory) declares `cc 2.0.0 – <3.0.0` and schema `1.0 – 2.0`; `cc 2.2.0` sits inside that window, so v0.4.0 did not move it.

The gate's failure vocabulary is closed and every member is fail-closed: `notFound`, `launchFailed`, `exit2(code, message)`, `parse`, `schemaOutOfRange`, `missingSecurityField`. **A missing security-relevant field is treated as unsafe, never as safe** — an absent `destructive`, `signed`, or `severity` reads as destructive, unsigned, and failing. The app never reads the CLI's stderr at all and never shows a raw error.

This gate is why schema drift is classified as a *security* event rather than a compatibility annoyance: a misread `fail` → `pass` would show green over a red pipeline, which is the highest-consequence integration risk in the product.

### B3 — Locating the helper, and refusing to guess

Resolution order is strict and deliberately excludes `$PATH`: an explicit override (only if executable) → **the bundle's own `Contents/Resources/cc`** → `~/.local/bin/cc` → `/opt/homebrew/bin/cc` → `/usr/local/bin/cc`. The app never invokes a bare name, because `Process.executableURL` does not consult `$PATH` by construction and because the bare name `copilot` collides with an unrelated tool.

The bundled helper is preferred over every machine-installed one. It is a 21.4 MB binary, SHA-256 pinned, **independently notarized**, and verified at release time by a gate that also confirms it was not re-signed. Child processes get a private 0700 `TMPDIR` under the app's own cache directory and the environment marker `COPILOT_MANAGED_BY=controltower`, which **disables the CLI's own self-update** so there is never a two-updater fight over the same binary.

### B4 — Concurrency: the CLI self-serializes; the app is not the lock

`update`, `onboard`, and `deprovision` serialize on a **`flock` over `copilot.lock`**, a global per-host mutex across all verbs, failing fast when held. Nothing in the app observes, references, or holds that lock. This is invariant #2 stated precisely: the app is not the serialization authority; the pipeline is. `onboard`'s in-transaction history repair is covered by `onboard`'s own lock, which is one of the reasons a standalone `repair` verb was never needed.

### B5 — The setup transaction: a preflighted saga, not an atomic write

This is the deepest backstage machinery in the service, and it is what the person experiences as a progress list and a Verify screen.

`cc onboard` runs **all deterministic preflight before any irreversible GitHub write**. At its core is one pure classifier over a closed set of **nine git-history states**, and the routing rule is narrow on purpose: **only a merge-base-proven fast-forward may auto-repair.** Every other state — dirty, ahead-only, diverged, diverged-with-identical-tree, wrong-origin, unreadable — routes to a human as `review` and stops the transaction before any personal-repository, SSH, store, or manifest mutation. Apply asserts `HEAD == target` as a postcondition. A run-scoped `completed_actions` ledger records every mutation. Compensation is never-destroy: **report, never delete.** Before any migrate or repair, the original manifest bytes are written to a content-addressed local rollback directory.

Row actions are a closed set — `reuse`, `create`, `migrate`, `repair`, `review` — and the guarantee that orphaned personal repositories are *adopted, never recreated* is structural rather than conventional: `create` can only be reached when a remote is genuinely missing, and an explicit HTTP 404 is the only accepted evidence of absence.

The live run proved this end to end: 16 of 16 layers, three previously-orphaned personal repositories adopted with their `created_at` timestamps byte-identical before and after, zero destructive git operations across three apply attempts, and a manifest written by a real apply rather than by hand.

### B6 — Materialize, and the never-destroy boundary

Materialization is a reconciling sync from local clones into the trees the assistants actually scan. Three trees have three different protections, and conflating any two of them is how the product's worst incident happened:

| Tree | Written by | Never-destroy treatment |
|---|---|---|
| Read-only mirror (`~/.copilot/mirrors/…`) | Only the pull path — fetch, reset, reclone | Disposable. May be reset or recloned freely |
| Materialized tree (what the host scans) | Only the pull path | Disposable. May be re-materialized freely |
| A human's working tree — a dirty personal checkout **or an author's tier-scoped authoring checkout** | The human | **Never touched.** Already covered by invariant #3 as written |

The consumer machine is read-only by construction, which is why a non-authoring person physically cannot produce a local conflict on shared content: there is nothing dirty in the mirror to conflict, and the only writable thing they own is the personal layer, which has its own protection. Conflicts exist only between *authors of the same tier*, at push time, against the remote — a lane that is deferred and has never carried a second writer.

Materialize also enforces the security posture that never weakens: production materialization is **fail-closed until executable remote content passes the ratified signature and policy check**. An item with no verifier wired in is blocked, not waved through. This is honest by intent and it is visible: it is why an apply that introduces brand-new layers legitimately reports blocked items.

### B7 — Entitlement, credentials, and the two things that never travel together

**Entitlement is GitHub repository access, and nothing else** (D3). Team membership grants read or write; selecting an entitled department syncs that layer onto the machine. There is no separate permissions system, no license server, no enrolment. The CLI computes entitlement by checking repository access per candidate layer; the app renders the resulting list and passes back a chosen id. `not-entitled` is a normal renderable outcome, not an error.

**Secrets never enter inheritance content or any git repository, at any tier, public or private.** Inheritance content carries `requires_secret: <NAME>` references only. The carriers are the per-user OS keychain and, optionally, a tier-scoped, organization-managed shared secret store — self-hosted Infisical — whose **endpoint** is delivered via inherited org config (the endpoint is not a secret; access stays gated by the person's own GitHub team membership). **Git push credentials are always per-user, on-device, and are explicitly excluded from the shared store.**

The `connections` verb is where this model becomes visible without ever becoming leaky. Backstage, it shells `copilot --json layers` against a CLI Copilot foundation carrying per-service `requires_secret` / `store_scope` declarations, then **presence-checks the hinted secret names** against the organization's store with **one `secret list` call per run, never one per name** — reading which names exist, never any value. It is read-only and takes no lock. The result is a per-row `secret_state` and, for unready rows, a list of missing *names*. Control Tower receives names and a state; it never receives, requests, or stores a credential.

### B8 — The admin engine: the script decides, the app renders

The Admin app computes no organizational state. The deterministic engine is `scripts/admin_bootstrap.sh` — 98 KB of bash whose own header states the contract: *the script, never the model, makes every existence and idempotency decision; every mutation is check-then-act (GET before POST/PATCH/PUT); nothing is ever forced, skipped past, or overwritten.*

Its dependencies are deliberately tiny and mostly vendored into the app bundle: `gh` and `jq` ship inside `Contents/Resources/`, alongside stock `python3` (used solely to parse the brief's YAML front matter) and `/usr/bin/curl` (used solely for a bounded store-reachability check). Foundation version floors are pinned in the script as fully-specified caret ranges, per product, so that a major version of one product can never be mistaken for a version of another. The content-bearing work branch is fixed and deterministic — never timestamped, never force-pushed, reused and fast-forwarded across re-runs.

The execution model is itself a service-design decision: **the app teaches and verifies; Claude Code executes.** The app collects the organization's description, produces a human-reviewable markdown brief saved to the machine, and hands it off; the app's Setup check then renders GitHub's own truth afterward. In v1 the app never fires the mutation itself.

### B9 — The release train: how a trustworthy artifact is manufactured

One pipeline, run locally, gating every release: build with `swiftc` → sign → verify the vendored helper by checksum and confirm it was not re-signed → verify the signed app carries the required automation entitlement and purpose string → run the app's own **headless Detect** (the exact three production calls, through the production client, printing typed JSON, exiting before any UI is created) → run the **headless setup transaction**, driving the real wizard model from Set up through Verify against an inert fixture helper while independently asserting which commands were sent → schema-compatibility gate → notarization-order gate → notarize → staple → Gatekeeper assessment → DMG → retained release directory with checksums, compat pin, notarization records, and metadata.

The testing shape that pipeline encodes was learned from an incident and is stated in the incident record: **test the state engine directly, test the app's typed seam headlessly, then run the same headless command against the final packaged artifact. Opening the UI is a visual-product check, not the primary integration test.**

Two selftest guards are worth naming because they defend the backstage from itself: the setup-transaction selftest refuses to run unless it is explicitly permitted **and** the helper's filename is literally `mock-cc` — an arbitrary helper path must never be able to turn a selftest into a live mutation.

---

## Support Processes

| System | What the service depends on it for | Failure posture |
|---|---|---|
| **GitHub** | The entitlement spine (team membership), device-flow identity, repository hosting for all 16 layers, the org's `ecosystem.yml` config-of-record, admin distribution via a private release | Degrades to honest holding states. `not-entitled` renders; an expired or revoked token surfaces as the `key` badge and one sign-in action |
| **The organization's GitHub OAuth App** | Device-flow client ID for the person's Connect GitHub step. **Per-company by ratified decision**, created during standup, client ID (not a secret) travelling in inherited org config | If never created, the person's first real action has nothing to authenticate against — an H1 handoff failure |
| **Shared secret store (self-hosted Infisical)** | Presence-checking declared credential names at tier scope; endpoint delivered via inherited org config | **Optional and deferrable.** Unreachable renders as a deferred, non-blocking stage; rows read `no-store` honestly. A phantom provisioner that could report a store as configured when it was not was fixed in `cc 2.2.0` |
| **The vendored `cc` helper** | Every verdict in the product | Pinned by SHA-256, independently notarized, preferred over any machine-installed copy, release-gated against re-signing |
| **Apple notarization / stapling / Gatekeeper** | The person's first frontstage moment: an app that opens | Release-blocking. Notarization order is itself gated by a test |
| **Foundation snapshot signing** | Signed, parentless snapshot commits for foundation-tier releases, verified against compiled-in allowed signers | Fail-closed. Unverified executable content is blocked, never materialized |
| **`copilot.lock` + `flock`** | Serializing all mutating verbs per host | Fail-fast when held. The app neither holds nor observes it |
| **`controltower.compat.json`** | The declared compatibility window between app, helper, schema, reader, and optional hooks | Both-direction gate: a helper older than the floor is as fatal as one newer |
| **Optional Discord hook transport** | A convenience bridge, entirely outside the critical path | **Codified fail-open**, with a bounded internal timeout — the direct, permanent output of the outage described below |

---

## Failure Points

*Ordered by demonstrated blast radius. Every entry below actually happened or is a currently-open gap; none is hypothetical.*

### F1 — A manifest field rename took down every Claude Code prompt · **PROVEN, remediated**

The ecosystem's layer manifest migrated from `component:` to `product:`. CLI Copilot's resolver still filtered on `component:`, found zero matching entries, and — this is the actual defect — **treated "zero matches" as the ordinary foundation-only state** rather than as schema drift. It loaded the public foundation only. The organization's `discord` command, which lives in the org overlay, vanished from the command tree. The user-level `UserPromptSubmit` hook then invoked `copilot discord …`, which no longer existed, and exited nonzero. Claude Code correctly treats a nonzero `UserPromptSubmit` hook as a prompt rejection.

**An optional notification transport became a total harness outage. Every prompt was rejected, regardless of content.**

The controls that now stand, all shipped: `product` is canonical with exactly one release of bounded legacy read compatibility and a hard error on conflicting dual declarations; a writer may not publish a schema change merely because its own validator accepts it — `cc onboard` now asks the installed reader to *prove* the resulting chain before moving the live pointer, applies downstream changes before moving it, restores exact prior bytes on failure, and refuses rollback if another process changed the candidate concurrently; hook shims are **transport fail-open** (success with a concise diagnostic when the command is absent or fails, stdout preserved when it succeeds), which is codified in the compat pin as `optional_hooks.policy: fail-open` with a bounded timeout; and a packaged N-1/N reader gate now tests the *exact shipped artifacts* against legacy, canonical, matching-dual, and conflicting manifests.

**The transferable lesson, and the reason this is F1:** the failure crossed four repositories and turned an optional convenience into a total outage. The blast radius of a shared-contract change is the union of every consumer, and a consumer that cannot distinguish "legitimately empty" from "I no longer understand this format" will always fail silently in the most expensive direction.

### F2 — The app worked from a terminal and failed from Finder · **PROVEN, remediated**

Control Tower correctly located its bundle-relative helper by absolute path. That helper then located *its own* `copilot` dependency by searching `$PATH`. Finder launches an app with `/usr/bin:/bin:/usr/sbin:/sbin`, so a Homebrew-installed `copilot` disappeared even though it was installed and working. The person saw "the installed `copilot` command is unavailable" on a machine where it plainly was available.

Three testing gaps allowed it to ship, and all three are instructive: app tests replaced the helper with a mock and therefore stopped at the app/CLI boundary, never exercising the real helper's own dependencies; the upstream release probe erased the whole environment instead of changing only `PATH`, and accepted any non-crashing report without requiring a real manifest inspection; and the branch producing the helper had no CI for its onboarding contracts.

The repaired boundary is one rule: **the helper owns machine inventory and resolves every direct dependency to a canonical absolute executable; the app stays parse-only.** Both the UI and the headless runner call the same production seam; neither reimplements inventory.

### F3 — Honest imperfection rolled back verified work, twice · **PROVEN, remediated in `cc` 2.1.1 and 2.1.2**

In the live run, a complete and correct 16-layer manifest write was undone twice by gates that were treating truthfulness as failure.

**First:** the transaction treated *any* non-zero materialize exit as fatal — including `held`, which is a passive, protective non-write. Four items were held because the new symlink guard was correctly refusing to write through a symlink escaping the materialize root; forty-eight were blocked because the fail-closed policy default blocks any executable item with no signature verifier wired in yet. Neither is a defect. Both rolled back the manifest. Worse, the **rollback-confirmation step re-ran the same failing gates against the restored manifest**, so it could not prove its own success and self-reported `rollback-failed` over a file that was byte-identical to its baseline. A false negative about the system's own safety.

**Second, after the first fix:** the post-materialize health check rolled back on anything short of `healthy`. A brand-new layer legitimately cannot have a positive freshness pointer or a local mirror on its very first appearance in a manifest — the signal is designed around already-established layers. Nine checkers reported `warn`; **zero reported `fail`**; the aggregate label read `offline`; the manifest write was undone.

Both fixes narrowed the gate rather than weakening it: rollback now only triggers on a genuine environment failure, rollback confirmation is a direct byte comparison of the file, the health gate counts `fail`-severity checkers directly rather than reading an aggregate label, and cold-start mirrors are seeded before the check. **The pattern worth naming: a fail-closed system that cannot distinguish "honestly imperfect" from "broken" will destroy its own correct work, and will do it deterministically.** Both were found only by a live run, both were root-caused by reading the diff rather than trusting the fix message, and neither was ever forced past.

### F4 — Never-destroy had a hole, and it cost 12,537 deletions · **PROVEN, remediated**

`~/.claude/knowledge` was a symlink into the organization's knowledge authoring checkout while simultaneously being the materialize target for the knowledge dimension. A routine update reconcile-deleted everything under the paths it owned there: 5 org agent extensions including the brand-voice binding, 16 agents, all commands, all memory, hooks and skills, 10 of 11 top-level docs files, and the knowledge manifest — **12,537 deletions in one commit, which a backup cron then pushed to origin.**

The root cause was two-fold and precise: the personal-tree guard protected a path only if it was a *registered* personal root or a *currently dirty* git tree, and a clean authoring checkout is neither; and the registered-roots list had no production feeder, so that branch never fired for a real authoring checkout. Content was restored and pushed. A guard now refuses to write or delete through any symlink escaping the materialize root — and that guard is the source of the four `held` items in F3, which is a good illustration of how a safety mechanism looks from the inside: like an incomplete transaction.

The documented procedure is now unambiguous: **never elevate content by symlink, and never point a materialize target at an authoring checkout.** Elevation is always copy → commit → push into the tier repo's own working directory, which is safe independent of the guard's state.

### F5 — Conservative safety reads as a wall of problems · **OPEN, by design**

The history classifier checks `git status --porcelain` before it compares any SHA, and **any** non-empty output routes to `review` without fetching or ancestry-checking. In the live run this meant 6 of 7 present repositories landed on `review` — and in every case the non-emptiness was 100% *untracked* framework-materialization litter, not a single modified tracked file.

That is the correct, conservative reading of never-destroy: the classifier cannot distinguish someone's uncommitted edit from someone's scratch file without making exactly the judgment call this product has decided belongs to a human. **But it is also a real experience failure in waiting.** Nine review rows presented to a non-technical person is not safety, it is a wall. The opportunity — not built, not scheduled — is a frontstage translation layer that says *"we found files here we didn't put there, so we stopped"* rather than surfacing a count of review states.

### F6 — Two things the invariants promise that the shipping app does not do · **OPEN, documented honestly**

**The invariants are not machine-enforced on the shipping binary.** All 40 fitness tests scan the retired Rust tree and cannot see one line of the shipping Swift; the CI job that would run them is disabled. Several native-side invariants *are* genuinely enforced — never a bare CLI name, the fail-closed schema gate, the selftest that refuses a non-mock helper — but by code review and shell harnesses, not by the named fitness functions. Porting the suite to scan the shipping sources is an open item.

**The crash-only watchdog is not implemented.** Invariant #2 describes a launchd watchdog with `KeepAlive={SuccessfulExit:false}` and never `true`. The packaging assets and the plist test exist; the shipping app neither installs nor manages the LaunchAgent. If the tray dies, nothing restarts it.

The owner's ratified position of 2026-08-02 is to **document both as named open items** rather than fix them in this pass or quietly reframe them away. Both are recorded here because a blueprint that claimed enforcement the product does not have would be repeating the exact defect this rebuild exists to correct. The mitigation for the watchdog gap is the product's own founding property: if the face dies, the pipeline is still correct — the person loses their window, not their environment.

### F7 — A backstage component that lied about its own readiness · **PROVEN, remediated in `cc` 2.2.0**

A phantom secret-store provisioner could report a store as configured when it was not. This is the most soul-relevant failure in the list: not an outage, not data loss, but a **false-positive readiness claim** — the exact class the product's whole honesty discipline exists to prevent, occurring in the backstage rather than in the icon. It was fixed alongside the connections bridge, and the secret-store onboarding stage now checks against the real store identity surface rather than a stale placeholder.

### F8 — Silent-failure surface: where this service could still fail without telling anyone

Named explicitly because the facilitation guide asks for it. **The 300-second poll is the only heartbeat, and nothing monitors it** — if it silently stops, the glyph freezes on its last honest state and looks exactly like success. **No telemetry exists**, so nothing detects a stuck fleet; the Analytics surface has a toggle and no emitter. **No fleet dashboard exists**, so an admin learns of a stuck person only when that person speaks. **A person who abandons the wizard mid-way leaves no signal anywhere.** Each of these is a deliberate consequence of choosing a small audit surface over observability, and each is a real cost of that choice rather than an oversight.

---

## Emotional journey and moments of truth

*Specific states, not adjectives. The moments where this service is won or lost.*

| Moment | The felt state | Why it is a moment of truth |
|---|---|---|
| Opening a downloaded DMG | Low-grade suspicion — "is this going to be a fight with my Mac?" | Gatekeeper stopping the person here ends the journey before the product has said a word. The entire notarize-and-staple pipeline exists for this one second |
| The device-flow code, waiting on the browser | Mild exposure — "I've just connected my work GitHub to something I don't understand" | The first act of trust, and it is asked for immediately. It is why the sign-in seam is built to hold no token by construction, not merely by convention |
| Detect, running | Suspended judgment — "it's looking at my machine and I can't see what it found" | Named phases, no percentage. An honest "here's the phase" beats a confident countdown that turns out to be wrong |
| Seeing "Your connections" populated with the organization's real roster | Recognition — "this knows my company, not just my laptop" | The v0.4.0 addition. Before it, this step could render empty, which reads as *nothing is here for me* |
| Pressing **Set up** | The single sharpest anxiety in the product — "what if it doesn't work and I've broken something?" | The founding anxiety from the owner interview. Answered by preflight-before-any-irreversible-write, adopt-never-recreate, and a mutation ledger — none of which the person sees, all of which they feel as *nothing bad happened* |
| The Done send-off | Deliberate elation — "You have the tools. Now go change the world!" | An owner-overridden peak in an otherwise flat register. One of exactly three |
| The first day of silence after Verify | Unease — "is it working, or has it just stopped?" | The H2 transition. The product's success state and its failure state look identical to a newcomer, and this is the least-validated moment in the service |
| A badge appears for the first time | Startle, then either relief or resentment | Determined entirely by whether the sentence names something the person can act on. One unactionable alert burns the credibility of the one that matters |
| Reading "Couldn't confirm" | Relief, if the copy earns it — "it didn't pretend" | A first-class honest state. This product would rather say *I don't know* than guess, and the whole trust model depends on that reading as competence rather than weakness |
| Being told to review your own uncommitted work | Ownership, ideally — "it stopped because that's mine" | Never-destroy made visible. F5 is the risk that this reads as obstruction instead |
| Copying a diagnostic report to send onward | Dignity, or defeat | The recovery-as-handoff design. The difference between a dead end and a door is entirely in this one affordance |

---

## Blueprint Diagram

```
TIME ────────────────────────────────────────────────────────────────────────────────────────►

           S0 STANDUP        S1 GET IT       S2 FIRST RUN        S3 STEADY      S4 CHANGE      S5 WRONG        S6 GOVERN
           (admin)           (person)        (person)            (person)       (person)       (person)        (admin)

CUSTOMER   describe org ·    download ·      connect GitHub ·    glance ·       Sync now ·     read one       add dept ·
ACTIONS    connect store ·   open DMG        pick department ·   do nothing     What changed · sentence ·      someone left ·
           review · hand                     press Set up                       join a dept    do the one     connect store
           off · check                                                                          thing that's
                                                                                                theirs
──────────────────────────────────── LINE OF INTERACTION ────────────────────────────────────────
FRONTSTAGE 16 admin         download page ·  9-stage wizard ·    aviator glyph  popover ·      H1–H7 holding  5 governance
           surfaces ·       signed DMG       named phases ·      + 1 of 12      Recently list  copy · 5       surfaces ·
           orientation-                      no ETA · roster     badges ·       · empty state  triage         org-setup
           before-input                      of 20 services ·    one plain      that says      categories ·   summary
                                             5 project          sentence ·      nothing        diagnose ·
                                             categories ·        Settings 4×4   changed        copy handoff
                                             playful Done
────────────────────────────── LINE OF VISIBILITY ───────────────────────────────────────────────
BACKSTAGE  admin_bootstrap  build · sign ·   auth login/grant ·  freshness      update ·       workspace       layers ·
           .sh: check-then- verify vendored  layers · doctor ·   (cheap SHA     update         verify/plan/    onboard --org ·
           act, GET before  cc · headless    connections ·       poll, 300 s)   --fanout ·     configure ·     store token
           POST · vendored  detect ·         onboard plan →      · doctor       update         revert ·        rotation
           gh + jq · fixed  headless setup   preflight → apply                  --project      onboard resume
           work branch ·    txn · notarize · · 9-state
           per-product      staple ·         classifier ·
           foundation pins  Gatekeeper       ledger · rollback
                                             copy · materialize
                                             (fail-closed)
           ── every one of these is `--json`, schema-gated per verb, fail-closed on a missing security field ──
           ── mutating verbs serialize on flock(copilot.lock); the app is NOT the lock ──
────────────────────────────── LINE OF INTERNAL INTERACTION ─────────────────────────────────────
SUPPORT    GitHub org ·     Apple notary ·   GitHub device flow  GitHub ·       GitHub ·       GitHub ·        GitHub teams ·
PROCESSES  teams · repos ·  Developer ID ·   · repo access =     Infisical      Infisical      the person's    Infisical
           ecosystem.yml ·  Gatekeeper       entitlement ·                                     own assistant   token rotation
           per-org OAuth                     Infisical presence                                (Claude/Codex)
           App · Infisical                   check (names only)
────────────────────────────────────────────────────────────────────────────────────────────────
FAILURE    H1 handoff       F2 launch-env    F3 honest work      F8 silent      F1 shared-     F5 conservative F6 no fleet
POINTS     carries only     PATH divergence  rolled back ·       poll death ·   contract       safety reads    visibility ·
           2 things ·       (fixed)          F4 symlink escape   F6 no watchdog drift across   as a wall ·     escalation is
           F7 store lied                     (fixed) · F5 review                4 repos        H2 silence      person-carried
           about readiness                   wall                 (fixed)       reads as death
           (fixed)
```

---

## Acceptance criteria for this blueprint

Verifiable, and each one traceable to evidence in this repository rather than to intent.

1. **Touchpoint cohesion.** Every frontstage element above maps to a named surface in `native/*.swift` or `scripts/admin_bootstrap.sh`; no aspirational surface is described as shipping. The two frontstage elements with no working backstage — the Analytics toggle, and the watchdog invariant — are named as such.
2. **No verdict is computed in the app.** Every state a person reads traces to a CLI field. The two most tempting places to break this — project classification and connection readiness — are both single-field filters over CLI-authored values, with unrecognized values failing closed rather than reading as ready.
3. **The deferred lanes are labelled as deferred.** `repair` and `publish` appear nowhere as existing verbs; the author lane carries its manual substitute and its unvalidated stamp.
4. **Every failure point cites evidence.** F1, F2, F3, F4, F7 are recorded incidents with remediation shipped in a named version. F5, F6, F8 are open gaps stated without softening.
5. **The open items survive into the next phase unresolved and unhidden:** the V-5 cold-laptop proof; the publicize step; invariant enforcement on the shipping binary; the absent watchdog; escalation with no fleet visibility; and the fact that **no independent non-technical person has completed this journey**, which makes the entire person lane a well-evidenced design against an unvalidated model.

---

**Related:** [Self-Interview](../01-research/10-interviews/01-interview-self.md) | [Journey Maps](20-journey-maps.md) | [JTBD](30-jtbd.md) | [Moments That Matter](40-moments-that-matter.md) | [CLI Contract](../../01-architecture/cli-contract.md) | [Inheritance & Publish](../../01-architecture/inheritance-and-publish.md) | [SOUL.md](../../../SOUL.md)
