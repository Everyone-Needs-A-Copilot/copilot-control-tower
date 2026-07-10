# Copilot Control Tower — Admin Flow (drive-the-agent)

|  |  |
|---|---|
| **Stage** | UXD interaction/IA for **Admin mode**. Layers the agentic-bootstrap engine (`admin-agentic-setup.md`) onto the ratified Admin surface (`control-tower-native-experience-architecture.md` §3.H, `control-tower-interaction-spec.md` §5). Reuses ~90% of the established Admin mechanics; adds two spine surfaces (Connect GitHub, Review & run) and reframes GitHub topology from teach-and-verify to **trigger-and-render**. |
| **Reads on** | `docs/03-design/admin-agentic-setup.md` (the engine + the GitHub sequence + integration-per-layer + the parse-never-compute Admin seam + its 5 open decisions), `docs/reference/copilot-solutioning-ecosystem.md` + `docs/reference/cse-alignment-decisions.md` (D1–D10, no MDM), `docs/03-design/control-tower-native-experience-architecture.md` (S4 = Onboarding + Governance, Quiet Instrument), `docs/03-design/control-tower-interaction-spec.md` §5 (Admin interaction mechanics reused wholesale), `docs/03-design/control-tower-copy-deck.md` Surface 3 (the authored strings). |
| **Voice** | Air-traffic controller for **Earl** (the technical operator standing up the org): calm, factual, unhurried, names the owner of every fix, no aggregate score, no time estimates, no raw errors, **no em-dashes**. Uses the copy deck strings verbatim for every surface it covers; new-surface copy is marked `[cw]` placeholder in the exact voice. |
| **Governing invariants** | #1 parse-never-compute (the app collects + renders; the engine computes + executes; no `gh`/GitHub logic in Swift) · #3 never-destroy (additive/idempotent, `already-present` reads calm) · #4 security inherited-not-weakened (no `--force`/`--skip-verify`; refuse on missing scope, never bypass) · #5 route by competence · #6 one-way inheritance, secrets never in git (leak-scan before push; secret-shape refusal on every field). |

---

## 0. What this is: the reframe

Admin mode is where a founder/operator stands up their org's **CSE tooling** (Knowledge / CLI / Claude / Codex Copilot) across the shared tiers (foundation → org → department) on GitHub, then governs it over time. It manages **components × shared tiers**, never products, never personal (D1/D2/D10).

**Two faces, one binary.** The shipped app is one signed binary with a user face (tray + wizard, for Bob) and an Admin face (this document, for Earl). The Admin face is reached only when `admin_capable` is true, and when false its entry point is **absent, not disabled** — exposure itself is the harm (native-arch §2). The user is structurally unable to reach any Admin action.

**Three faces, one engine.** The Admin *GUI* is one of three faces over the same deterministic engine (`admin-agentic-setup.md` §1.1): the open-source **skill** (Claude Code / Codex), this **GUI**, and the headless **CLI verb** (`copilot admin bootstrap --json`). All three collect the same inputs and render the same streamed per-step JSON. The GUI never calls `gh` or the GitHub API; it shells to the verb and renders (§10).

**The one interaction shift this doc makes.** The prior Admin design taught the operator the GitHub topology and verified it by hand. The engine upgrades that to **drive-the-agent**: the operator *configures*, then *fires* one bootstrap, and the GUI *renders the engine's streamed steps* as they land. The operator drives; the engine acts; the app renders. Nothing about repos, teams, grants, seed authorship, or leak-scan is computed in Swift.

---

## 1. JTBD statements (per flow)

- **Enter Admin (ADM-0):** *When I am the person setting this up for my organization, I want to cross into the org-standup tool from the same app my team uses, so I do the admin work in one place without a second install and without my team ever seeing it.*
- **Connect GitHub (ADM-3):** *When I start a standup, I want the app to check my GitHub access can do the job before it changes anything, and tell me exactly how to fix it if it can't, so I never half-create an org or get told to bypass a safety check.*
- **Configure (ADM-4..7):** *When I describe my org (its name, its departments, which shared integrations actually exist at each layer, and who is on each team), I want constrained forms that make an invalid setup hard to author, so the engine has everything it needs and I never hand-edit a file.*
- **Review & run (ADM-8):** *When I have described my org, I want to fire one setup and watch each repo, team, grant, and seed land honestly, knowing a re-run is safe and nothing already there is clobbered, so I trust what just happened to my GitHub org.*
- **Setup check (ADM-9):** *Before I hand the org its setup, I want an honest red and green list where every red names who has to fix it, so I never roll out on a broken foundation and always know who to chase.*
- **Govern (ADM-G*):** *When my org changes over time (a new department, a new integration, a new hire, someone leaving), I want to add or offboard by re-running the same safe engine or by rendering a revocation, so steady-state governance is the same instrument as standup.*

---

## 2. Surface inventory (IDs)

All live inside **S4 Admin mode** (native-arch surface map). Onboarding is a do-once, revisitable pipeline; Governance is occasional. New spine surfaces are marked **NEW**; the rest reuse the ratified §5 surfaces and the copy deck labels.

| ID | Surface | Sidebar label (copy deck §3.2) | Role | Reuses / New |
|---|---|---|---|---|
| **ADM-0** | Entry / handoff into Admin | (window frame + handoff header) | Cross from user face; orient "where is the baton" | Reused (native-arch §3.H) |
| **ADM-1** | Prerequisites | `Prerequisites` | TEACH what you need on hand (org exists, an owner, billing) | Reused (copy §3.3) |
| **ADM-2** | Contacts | `Contacts` | Record publisher / admin / point-of-contact | Reused (copy §3.4) |
| **ADM-3** | **Connect GitHub** | `Connect GitHub` **NEW** | The engine's step-0 auth+scope preflight; **refuses on missing scope**, teaches the fix | **NEW spine** (engine §1.3 step 0) |
| **ADM-4** | Departments & access | `Repositories & teams` | Org identity + departments-as-you-go + **integration-per-layer** + members/team grants (the COLLECT phase) | Reused + extended (copy §3.5; integrations §2 of engine) |
| **ADM-5** | Secret store | `Secret store` | Connect the shared store by endpoint + team scope; secret-shape refusal | Reused (copy §3.6) |
| **ADM-6** | Seed | `Seed` | Assemble `ecosystem.yml` (components, depts, pins, integration refs, signers) | Reused (copy §3.7) |
| **ADM-7** | Policy signers | `Policy signers` | Sign the capability policy; CODEOWNERS/rulesets | Reused (native-arch §3.H) |
| **ADM-8** | **Review & run** | `Review & run` **NEW** | The trigger-and-render moment: fire `copilot admin bootstrap --json`, render streamed steps | **NEW spine** (engine §1.3, §3) |
| **ADM-9** | Preflight (setup check) | `Preflight` | Red/green, owner-named, no aggregate score | Reused (copy §3.8) |
| **ADM-G1** | Governance: add / offboard | (Governance › Deprovision + add-department re-run) | Add-department no-op re-run; deprovision-by-revocation render | Reused + extended (copy §3.9) |
| **ADM-G2** | Governance: Analytics | `Analytics` | Off-by-default usage data | Reused (copy §3.10) |
| **ADM-G3** | Governance: Secret store config | `Secret store config` | Read-only render of inherited endpoint | Reused (copy §3.11) |
| **ADM-SKILL** | The OSS skill path | (outside the app) | Same engine, run in Claude Code / Codex; un-gated | **NEW relationship** (engine §3, §1.1) |

Deliberately **NOT** a surface (D4, unchanged): any MDM profile / `.mobileconfig`, the 19-key managed-key collector, an MDM upload walkthrough, a Fleet dashboard as center-of-gravity, or any control that re-points the update feed / mirror / secret-store endpoint from user config.

---

## 3. Admin IA and navigation (reused frame)

One `Window` scene, left navigation sidebar in two sections, standard macOS source-list interaction (single selection drives the detail pane). Reused verbatim from interaction-spec §5.2, with the two NEW spine items placed in reading order so the sidebar reads as the drive-the-agent pipeline.

```
┌──────────────────── Administration ─────────────────────────────┐
│ HANDOFF: Publisher done · Setup v1.4.2 · Next: you (Admin)       │  read-only, rendered
├──────────────────┬───────────────────────────────────────────────┤
│ ONBOARDING       │  DETAIL PANE (selected item)                  │
│  ✓ Prerequisites │                                               │
│  ✓ Contacts      │                                               │
│  ◉ Connect GitHub│   ← the gate: nothing mutates before it passes│
│  ○ Departments & │                                               │
│    access        │                                               │
│  ○ Secret store  │      (the COLLECT surfaces feed one engine)   │
│  ○ Seed          │                                               │
│  ○ Policy signers│                                               │
│  ○ Review & run  │   ← the trigger-and-render moment             │
│  ○ Preflight     │                                               │
│ GOVERNANCE       │                                               │
│  Add / offboard  │                                               │
│  Analytics       │                                               │
│  Secret store    │                                               │
│  config          │                                               │
└──────────────────┴───────────────────────────────────────────────┘
```

- **Handoff header** (persistent, read-only, whenever Onboarding is active) renders `{publisher, admin, artifact_ref, next_owner}` verbatim from the CLI contract (parse-never-compute; TA to place the object). Copy deck §3.1: `Publisher done · Setup v1.4.2 · Next: you (Admin)`; not-started: `Not started yet`. When `next_owner` is the admin, the current onboarding step is subtly emphasized. It answers "where is the baton" at every moment.
- **Onboarding items are a do-once progression** with per-item done/current/upcoming marks (same roadmap grammar as the wizard and Publisher Setup, Nielsen #4). Each item is individually revisitable; the checklist shows what remains. **Connect GitHub gates everything downstream:** Review & run is inert until the auth+scope preflight passes (the engine refuses to mutate before step 0, §1.4 of the engine spec, invariant #4).
- Admin and Settings may be open at once (different authorities); each is modeless. Nothing here ever blocks the whole app; the user-face glyph stays live and honest.

---

## 4. ADM-0 — Entry / handoff into Admin mode

**Two faces, one binary; how the operator crosses in.**

- **Becoming admin-capable.** `admin_capable` is a first-run opt-in on the (only) unmanaged machine kind: the wizard's Welcome step carries one low-key secondary control, off by default, phrased as a role declaration: copy deck §2.1 `I'm setting this up for my organization.` Choosing it sets the local `admin_capable = true` fact. There is no MDM grant path (D4). (Path 2a vs 2b is an owner decision, §14 Q6.)
- **Entering.** When `admin_capable` is true, two entry points appear, both off the same fact: the right-click menu item `Open Administration...` (copy §1.9) and a conditional `Administration` tab in Settings (copy §4.3). When false, both are **absent, not disabled** (structural hiding). Opening calls `NSApp.activate(ignoringOtherApps:)` then `makeKeyAndOrderFront` so the window comes forward from the background utility (spec §1.2).
- **Landing.** The window opens on the first incomplete Onboarding item (or Prerequisites on a fresh machine), with the handoff header already populated from the Publisher→Admin handoff block (artifact_ref + Team ID + version + update-signing status, native-arch §3.I). The operator always lands knowing what is done and who holds the baton.
- **Leaving.** Close box / `Cmd-w`; on last-window close the app demotes to pure accessory presence. Admin state persists (it is server/GitHub truth, re-read on next open); nothing is lost by closing mid-pipeline.

**Drive-and-render seam.** App COLLECTS: the `admin_capable` opt-in (a local role declaration). App RENDERS: the handoff object. Engine: none yet (no mutation on entry).

**States (idle/working/streamed-step/done/degraded/refused):** *idle* = window open, handoff header shown, first item selected. *degraded* = handoff object unreadable → the honest `I couldn't read the result of this, so I won't guess.` line, header shows `Not started yet`, never a fabricated baton. *refused* = n/a (entry mutates nothing). *working/streamed-step/done* = n/a here (they belong to ADM-8).

---

## 5. ADM-3 — Connect GitHub (the auth+scope preflight, refuse-not-weaken)

This is the engine's **step 0** surfaced as its own gate. It is distinct from per-user consumption sign-in (device-flow, S5): this is **org-owner administration** using the admin's own `gh` credential (HTTPS + token) with elevated scopes `repo` + `admin:org` (engine §1.3 Auth model). The GUI never holds the token; it triggers the capability, which uses the admin's own on-device `gh`.

**Flow:**
1. On selecting Connect GitHub, the GUI fires the engine's preflight (`copilot admin bootstrap --verify` / the step-0 check) and renders the result. It checks: authenticated? actor is an **owner** of `<org>`? scopes `repo` + `admin:org` present?
2. **Pass** → a calm confirmation and the downstream items unlock. Placeholder copy `[cw]`: `Your GitHub access can set up <org>.` (owner-named, no green celebration).
3. **Refused** (the load-bearing case) → the engine refuses (exit 2) with a plain instruction and **no mutation has occurred**. The GUI renders the refusal by reason, and a single **Check again** action (re-runs the preflight). It **never** offers a bypass, a `--skip-verify`, or a `--force` (invariant #4 — the design's whole point here is that weakening posture is not an available affordance).

| Refusal reason (engine step 0) | Rendered line `[cw]` | Fix affordance |
|---|---|---|
| unauthenticated | `You're not signed in to GitHub yet, so I can't set up your organization.` | plain instruction: run `gh auth login`; then **Check again** |
| not an owner of `<org>` | `Your GitHub account isn't an owner of <org>, so it can't create the org's spaces. Ask an owner to run this, or to make you one.` | names the **GitHub org owner** as the fix owner; **Check again** |
| missing scope (`admin:org`/`repo`) | `Your GitHub sign-in is missing the access it needs to set up your organization.` | the exact command, verbatim and copyable: `gh auth refresh -s admin:org -s repo`; then **Check again**. No bypass. |
| org does not exist | `I can't find the <org> organization on GitHub. It has to be created on github.com first (that needs billing and a person).` | teach: the categorical-automation boundary (engine §1.4). Link out to github.com; **Check again** |

**Drive-and-render seam.** App COLLECTS: the org name (also used downstream) and the intent to check. App RENDERS: the pass/refuse result and the plain fix. Engine COMPUTES/EXECUTES: `gh auth status`, owner verification, scope check — **read-only, no mutation** (the engine never half-creates, §1.4).

**States:** *idle* = `Not checked yet.` + **Check access**. *working* = spinner-with-label `Checking your GitHub access...` (no ETA). *done* = pass line, downstream unlocked. *degraded* = the check itself could not run (io/exit) → honest `Something stopped me from checking your access, so I won't guess.` + **Check again**, downstream stays locked (fail-closed). *refused* = the table above; downstream stays locked. *streamed-step* = n/a (this is a single read).

**Keyboard/VoiceOver:** the refusal is a VO group announcing "GitHub access, not ready, and how to fix it"; the copyable command is a `.textSelection(.enabled)` element with a `Copy` affordance and a "Copied" confirmation; **Check again** is `.defaultAction`.

---

## 6. ADM-4..7 — Configure (the COLLECT phase)

Everything the engine needs, gathered through constrained forms so an invalid setup is hard to author (error prevention over handling, Nielsen #5). None of it mutates GitHub; it assembles the inputs the one bootstrap will act on. Four revisitable surfaces feed one engine.

### 6.1 ADM-4 Departments & access (org identity → departments-as-you-go → integration-per-layer → members)

Copy deck §3.5. Title `Departments and access`. Intro `Access is how someone joins a department. Give a team read access and its people can join the department. Give write access and they can author it.`

- **Org identity.** The org name (validated as a GitHub org slug; the same value ADM-3 checked). Read from / written to the seed.
- **Departments-as-you-go.** An add/remove-row list of departments (`copilot-dept-<unit>`, slugified per convention). Adding a department here is purely COLLECT; it becomes real only at Review & run. **Adding a department later is a no-op re-run** (§7, engine §1.3 departments-as-you-go): the engine runs only steps 3–6 for that unit and skips anything already present. The UI states this plainly so the operator trusts that returning to add "Marketing" next month touches nothing else.
- **Integration-per-layer (the "I don't have Workday" fix).** For **each layer** (org, and each department) the operator declares which shared integrations **exist** at that layer: an add-row list of `{ id, requires_secret: <NAME>, store_scope }`. This is the whole mechanism of **absence = non-existence** (engine §2): declaring Salesforce + Microsoft 365 at org but **not** Workday means no entitled user, at any tier, ever sees Workday. The form never accepts a secret value; `requires_secret` is a NAME, `store_scope` resolves against the inherited store endpoint (D4/D6). Each field runs the secret-shape refusal (§6.3 below).
  - *Presentation:* per-layer cards, each an add-row integration list. An **empty** layer card is honest ("No shared integrations at your organization yet") and is itself the mechanism, not a gap to fill.
  - *Constraint:* `id` is a picker from the org's classified integrations where the classification exists (§14 Q5, integration classification is open); free-text only where the classification does not yet constrain it, and even then the secret-shape refusal applies.
- **Members / team grants.** Per department, add people/teams to the grant; the grant **is** the entitlement (D3). Rendered in plain language, not raw permissions (copy §3.5): read grant `People on this team can join the Sales department.`; write grant `These people can author the Sales department.` This is the legibility that closes the loop with the user's "Available to join" row (interaction-spec §5.6): the operator sees the grant is what lights that row up. Applying a grant at standup is part of the bulk bootstrap (steps 3a–3c); a single later grant change effects one grant via the author's own credential and renders GitHub's truth (never computes access).

**Empty / loading / error / success (copy §3.5):** empty (no grants) `No one can join this department yet. Give a team read access to let them in.`; loading `Applying access...`; error `Couldn't change access right now. Try again.`; success `Access updated.`

### 6.2 ADM-5 Secret store

Copy deck §3.6. Title `Connect your shared secret store`. A short guided form: store type (picker), store address (a URL, validated on blur, `This is a web address, not a secret.`), and which teams can use it (team-chooser mapping teams to store scopes). **No secret is ever pasted here.** The endpoint becomes part of the inherited org config the seed/PR carries; it is not a secret (D4/D6). Success `Connected. This will be included when you open your setup pull request.`

### 6.3 The secret-shape refusal (hard constraint, reused across every configure field)

The load-bearing safety interaction (copy §3.6, engine §1.4 / §5.5 of the interaction spec). **Every** field in the configure phase (secret store, integration `requires_secret`, seed) runs a fail-closed secret-shape check on input (high-entropy strings, known key prefixes, `BEGIN PRIVATE KEY`, etc.). A value that looks like a secret is **rejected inline and blocked from being saved** (a constraint, error made impossible, not a warning dialog), with the plain refusal: `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.` The rejected value is not stored and not logged. This is the field-level counterpart to the engine's step-5 leak-scan (§7): defense in depth, structural separation the primary guarantee.

### 6.4 ADM-6 Seed / ADM-7 Policy signers

Copy deck §3.7 / native-arch §3.H, reused verbatim. The seed generator is the sectioned, progressively-disclosed form (Concepts A raw-YAML and B one-giant-form rejected in interaction-spec §5.4) with a live read-only preview (`What this will create`) and a single Validate-then-Open-PR action. **In the drive-the-agent model the seed feeds the engine:** the assembled `ecosystem.yml` (components, depts, version pins, integration definitions from ADM-4, `requires_secret` refs, store endpoint reference, `policy_signers`) is the artifact the bootstrap writes/merges additively at step 4. Sections (copy §3.7): `Copilots · Departments · Versions · Integration references · Policy signers · Usage data`. Validate summary is a **count, never a score**: `2 things to fix` / `Everything checks out.` Policy signers sign the capability policy and set CODEOWNERS/rulesets.

**Drive-and-render seam (whole configure phase).** App COLLECTS: org name, department list, per-layer integration declarations (`id` + `requires_secret` name + `store_scope`), member usernames per team, store endpoint + team scoping, seed sections, signers. App RENDERS: constrained-input validation, the seed preview, the secret-shape refusal. Engine: none yet — configure mutates nothing; it assembles inputs the one bootstrap acts on.

---

## 7. ADM-8 — Review & run (the trigger-and-render moment)

The heart of the drive-the-agent experience. The operator has configured; here they fire **one** bootstrap and watch the engine's streamed per-step JSON land. The app renders each step's outcome and **computes nothing**.

### 7.1 Concepts considered (novel: rendering a streamed agentic engine, no macOS precedent)

- **A — Fire-and-forget with a terminal-style log tail.** Stream the engine's stdout as a scrolling log. *Rejected:* raw log text violates "never a raw string" and the plain-language rule; a log tail gives no honest per-step outcome and buries `already-present` (the never-destroy reassurance) in noise. Weak on Nielsen #2 (match real world), #9 (recover from errors in plain language).
- **B — A single indeterminate spinner ("Setting up your organization...") then a done screen.** *Rejected:* fails #1 visibility of system status (the operator can't see which repo/team/grant landed), and hides idempotency (a re-run looks identical to a first run, so "is it safe to re-run?" is never answered). No moment where never-destroy becomes legible.
- **C — A live, ordered checklist that renders one row per engine step, each resolving in place to a plain outcome word (`Created` / `Already there` / `Skipped` / `Stopped` / the plain failure detail), with a plain summary count and no aggregate score.** **Selected.** Best on #1 (each step's status is visible as it lands), #2 (a checklist of named acts matches the operator's mental model of "create repo, create team, grant, seed, scan, verify"), #5/#9 (a `Stopped` row names its owner and how to fix, in plain language), and it makes idempotency **legible**: a re-run visibly reads as rows of `Already there`, and the summary says so. This is the direct sibling of the Preflight grammar (§8) and the wizard materialize (named phases, no ETA), so it inherits the established craft.

### 7.2 The run surface

```
Review & run
┌───────────────────────────────────────────────────────────┐
│  About to set up: acme-co · 2 departments (Sales, Eng)      │  read-only review of the COLLECT
│  Salesforce, Microsoft 365 at your organization             │
│  This adds and updates. It never deletes or overwrites      │  the never-destroy promise, up front
│  anything already there.                                    │
│                                           [ Set up my org ] │  the single trigger
└───────────────────────────────────────────────────────────┘

  (after trigger — streamed, rows resolve in place)
┌───────────────────────────────────────────────────────────┐
│  ✓ Checked your access                       Ready          │  step 0  pass
│  ✓ Set the org to read-only by default       Already set    │  step 1  already-present
│  ✓ Created your organization space           Created        │  step 2  created
│  ◐ Setting up the Sales department...         Working        │  step 3  streamed / working
│  ○ Sales team                                 Waiting        │  step 3a upcoming
│  ○ Who can join Sales                         Waiting        │  step 3b grant (entitlement)
│  ○ Add people to Sales                        Waiting        │  step 3c members
│  ○ Write your setup file                      Waiting        │  step 4  seed merge
│  ○ Safety check                               Waiting        │  step 5  leak-scan
│  ○ Setup check                                Waiting        │  step 6  verify → hands to ADM-9
├───────────────────────────────────────────────────────────┤
│  Summary: 1 created, 1 already there. Still working.        │  a count, never a score
└───────────────────────────────────────────────────────────┘
```

- **One trigger.** A single primary button (`[cw]` `Set up my org`), enabled only when Connect GitHub passed and the configure phase validates. Above it, a read-only review of what will happen and the never-destroy promise **stated up front**: `[cw]` `This adds and updates. It never deletes or overwrites anything already there.`
- **Streamed rows.** The engine emits `{step, result, detail}` per step (engine §1.3). Each row resolves in place from `Waiting` → `Working` → a plain outcome word. **Result tokens map to plain words** (`[cw]`, new strings — route to cw):

  | Engine `result` | Row word | Reads as | Row treatment |
  |---|---|---|---|
  | `created` | `Created` | a new thing made | quiet check + neutral |
  | `already-present` | `Already there` | **safe re-run, nothing clobbered** | quiet check, calm, **not** an error color |
  | `skipped` | `Skipped` | not needed | neutral dot |
  | `refused` | `Stopped` | a gate refused (see 7.3) | distinct firm mark + plain reason + owner |
  | `failed` | the plain `detail` | one step failed, the rest is intact | distinct mark + owner + retry |

- **Idempotent / additive / never-destroy, made legible.** `already-present` is the design's proof of never-destroy: it renders **calm and positive**, never as a warning. A full re-run (add-department, or just running again) reads as a column of `Already there`, and the summary says so plainly: `[cw]` `Nothing to redo. Everything's already in place.` The up-front promise and the outcome words together answer "is it safe to run this again?" before and after the fact.
- **No aggregate score, no ETA.** The summary is a plain **count** of the outcome words (`1 created, 1 already there`), a fact, never a percentage, gauge, or "8/10 done". Progress is the rows filling in; there is no time estimate and no percentage-as-promise (matches the wizard materialize and Preflight).
- **Hands to Preflight.** Step 6 (verify) hands directly to ADM-9; the run does not assert its own success — the honest verdict is the setup check.

### 7.3 Failure and refusal during the run

- **`refused` mid-run** (e.g. scope lost, or the step-5 **leak-scan** finds a secret-shaped value in the seed): the row renders `Stopped` with the plain reason and the owner. The leak-scan refusal is honest and firm: `[cw]` `I stopped before pushing because something in your setup looked like a secret. Setup files never carry secrets. Fix it and run again.` No push happened (fail-closed, invariant #6). The operator fixes in Seed/Secret store and re-runs; already-done steps read `Already there`.
- **`failed` mid-run:** the failing row names its owner and offers a scoped retry; **completed steps are not undone** (additive engine). Never a raw GitHub/git/serde string (copy discipline). Because every mutation is check-then-act and additive, a retry resumes safely.
- **Partial done:** the run never leaves a half-created state that a re-run can't safely reconcile — that is the engine's guarantee, and the UI's job is only to render it honestly and offer **Run again**.

**Drive-and-render seam.** App COLLECTS: the single trigger (and the already-gathered inputs, passed as flags/stdin). App RENDERS: the streamed per-step `{step, result, detail}`, the plain summary count, the never-destroy framing. Engine COMPUTES/EXECUTES: everything in engine §1.3 — existence checks, repo/team/grant creation, base-permission, seed authorship + merge, leak-scan, verify. The app **never** calls `gh`.

**States:**
- *idle* = the review card + trigger; nothing has run.
- *working* = the trigger swaps to a non-repeatable in-progress label; the current step shows `Working` with an inline indeterminate `ProgressView`; upcoming rows are `Waiting`.
- *streamed-step* = each `{step, result}` resolves its row in place (a polite VO live region announces the resolved row); the summary count updates.
- *done* = all rows resolved; summary is the plain count; a single forward action to **Run the setup check** (ADM-9). A clean re-run shows all `Already there` + `Nothing to redo.`
- *degraded* = the engine's stream became unreadable mid-run → honest `I couldn't read the rest of that, so I won't guess.` with **Run again**; already-resolved rows stay as rendered, never fabricated forward.
- *refused* = a `Stopped` row (7.3); no mutation past it; the fix is owner-named; **Run again** after fixing.

---

## 8. ADM-9 — Preflight (the setup check, verify)

Copy deck §3.8, reused verbatim; the honest verdict of the whole standup. Renders `PreflightReport` (`checks: PreflightCheckResult[]`, each `{check, status ∈ pass|fail|unknown, detail}`), CLI-computed (`copilot admin bootstrap --verify` / `copilot admin preflight`), app-rendered.

- **One row per check**, each a **shape + color + text** mark (never color alone): pass = quiet dot + `Ready`; fail = firm mark + the plain `detail`; **`unknown` is rendered distinctly and NEVER green** (`Couldn't check this`). The bootstrap contributes the rows in engine §4: org repo + base-read, department repos, team grants entitlement, members provisioned, seed valid + signed, shared store reachable, foundation reference resolves.
- **No aggregate score, ever.** Summary is a plain count: `2 things must be fixed. 1 couldn't be checked.` / when clean `Everything's ready to hand over.`
- **Every fail/unknown names its owner** (copy §3.8): `Publisher` / `Admin` / `You` / `The user`, plus the external owners the engine names (**GitHub org owner** for base-perm, **IT infra** for the store, **ENAC / external** for the foundation reference).
- **Drill-in / fix** (owner-appropriate): Admin-owned → **Go fix this** jumps to the offending onboarding step with the field focused (e.g. a seed parse failure jumps to ADM-6); others → the plain instruction + handoff reference; never a raw error, never a dead end.
- **Run model:** on-demand (`Run the setup check`), re-run always available (`Run it again`); rows fill progressively as checks arrive; no global ETA.

**States:** *idle/empty* (never run) = `Run the setup check before you hand this over. It catches blockers before your organization does.` + CTA. *working* = rows fill in. *streamed-step* = each check resolves in place. *done* = the count summary + per-row owners. *degraded* = a check that itself errored renders `unknown` with an honest reason, never a crash, never green. *refused* = n/a (read-only verify).

**Drive-and-render seam.** App COLLECTS: the run intent. App RENDERS: the check rows, owners, count. Engine COMPUTES: every verdict (unknown-never-green is the engine's, not the app's).

---

## 9. Governance steady-state (ADM-G*)

Steady-state governance is the **same instrument** as standup: adding a department, an integration, or a member is a safe re-run of the same engine; offboarding is a rendered revocation. No new mental model.

- **Add a department / integration / member (ADM-G1 add path).** Returning to ADM-4 to add "Marketing" (or a new integration at an existing layer, or a person to a team) and re-running ADM-8 runs only the affected steps and reads as `Already there` for everything else (engine §1.3 departments-as-you-go: a full no-op for existing units). The governance entry frames it plainly: `[cw]` `Add a department or a person here. Setting up again only adds what's new and never touches what's already there.`
- **Deprovision (ADM-G1, copy §3.9).** Title `Someone left`. **The app renders, it never triggers** (invariant #1/#5). It is a render of GitHub-access revocation + shared-secret-store token rotation (D4 — **no MDM wipe, no device wipe**). Outcome lines: `Their access was revoked and their shared keys were rotated.`; retained work prominent (`Their unsaved work was kept: <list>.` / `No unsaved personal work was in the way.`); removed count neutral (`<N> item(s) removed.`). The one line allowed to read as an alarm when secrets were involved: `Heads up: secrets were involved in this. Your IT team has been told.` Unreadable → `I couldn't read the result of this, so I won't guess.` Accepted residual (D4): content already on a departed person's disk is not remotely wiped.
- **Seed generator in governance.** The same ADM-6 surface edits the living `ecosystem.yml` additively (add a dept/integration/signer) and re-opens a PR; re-run never rewrites existing entries (engine §1.3 step 4).
- **Analytics (ADM-G2, copy §3.10):** off by default; a plain switch + read-only "What this would share"; no dark pattern.
- **Secret store config (ADM-G3, copy §3.11):** read-only render of the inherited endpoint; `This comes from your organization's signed setup. It isn't editable here, by design.` (honored only from signed inherited org config; never re-pointed from user config, invariant #4).

**States (add/offboard):** *idle* = the governance section, revisitable. *working/streamed-step/done* = an add re-run reuses ADM-8's run states. *degraded* = deprovision unreadable → honest holding. *refused* = n/a (governance renders or re-runs the same gated engine; the ADM-3 gate still applies to any add re-run).

---

## 10. ADM-SKILL — the two paths (same engine)

The GUI is not the only face. A person can download the open-source repo and run the **skill** in Claude Code / Codex instead of opening the GUI (engine §1.1, §3). Both drive the **same engine** and see the **same streamed per-step JSON**; the guarantees (idempotency, never-destroy, leak-scan) are contract-testable independent of any LLM.

- **Relationship for the operator.** The skill *is to the CLI what the GUI is to the CLI*: a face that gathers the same org/dept/integration/member inputs conversationally, checks the same `gh auth`/scopes, invokes the same verb, and narrates the same per-step results in plain language. If Control Tower vanished, the skill still stands up the org; if the LLM refuses, the verb still runs headless.
- **Gating differs by design.** The **GUI Admin surface** is gated by `admin_capable` (exposure is the harm). The **skill runs entirely outside the app** and is **not** gated by that boolean — it is the alternative path for an admin who never opens the GUI (engine §3). The gate governs the GUI surface, not the capability.
- **In-GUI acknowledgement (optional, read-only).** ADM-8's review card may carry one quiet, read-only line pointing at the skill for operators who prefer the terminal: `[cw]` `Prefer to run this from the terminal? The same setup is available as an open-source command.` No action, no second engine — just honesty that the paths are equivalent. (Whether to surface this at all is a light owner call; default: yes, one quiet line.)

---

## 11. The drive-and-render seam, consolidated (parse-never-compute per screen)

| Screen | App COLLECTS | App RENDERS | Engine COMPUTES / EXECUTES |
|---|---|---|---|
| ADM-0 Entry | `admin_capable` opt-in (role declaration) | handoff object | (nothing) |
| ADM-3 Connect GitHub | org name; check intent | pass/refuse + plain fix | `gh auth status`, owner + scope check (read-only) |
| ADM-4 Departments & access | org name, dept list, per-layer integration declarations, members/grants | constrained validation, plain grant language | (none until run) |
| ADM-5 Secret store | store type, endpoint URL, team scoping | URL validation, **secret-shape refusal** | (none until run) |
| ADM-6 Seed | seed sections | live preview, count summary, field errors | seed validation (`admin/seed.rs`) |
| ADM-7 Policy signers | signers, CODEOWNERS/rulesets | signer list | signing |
| ADM-8 Review & run | the single trigger + assembled inputs | streamed `{step, result, detail}`, count, never-destroy framing | **all of engine §1.3**: existence checks, repo/team/grant creation, base-perm, seed merge, leak-scan, verify |
| ADM-9 Preflight | run intent | check rows, owners, count | every verdict; unknown-never-green |
| ADM-G1 Deprovision | (nothing) | revocation + rotation outcome, retained work | server-side revocation (rendered, never triggered) |
| ADM-G3 Store config | (nothing) | inherited endpoint | (read-only, from signed inherited config) |

**The negative guarantee, stated once:** no `gh` call, no GitHub API call, no existence check, no idempotency decision, no leak-scan, and no red/green verdict is ever computed in Swift. The app is a face; the engine is the truth.

---

## 12. Per-screen run-state matrix (idle / working / streamed-step / done / degraded / refused)

The six run states the drive-the-agent surfaces share (form controls also carry the standard eight interactive states — default/hover/focus/active/disabled/loading/error/empty — per interaction-spec §5; the six below are the *flow* states this doc adds).

| Screen | idle | working | streamed-step | done | degraded | refused |
|---|---|---|---|---|---|---|
| **ADM-3 Connect GitHub** | `Not checked yet` + Check access | `Checking your GitHub access...` | n/a (single read) | pass line, downstream unlocked | check couldn't run → honest, downstream locked (fail-closed) | scope/owner/auth refusal + exact fix; **no bypass**; downstream locked |
| **ADM-8 Review & run** | review card + `Set up my org` | trigger non-repeatable, current step `Working` | rows resolve in place; count updates; polite live region | all rows resolved; count summary; → Run setup check | stream unreadable → `won't guess` + Run again | `Stopped` row (scope lost / leak-scan); no mutation past it; owner-named; Run again after fix |
| **ADM-9 Preflight** | never-run empty state + Run | rows fill progressively | each check resolves | count summary + per-row owners | a check errored → `unknown`, never green | n/a (read-only) |
| **ADM-G1 Add re-run** | governance entry | reuses ADM-8 working | reuses ADM-8 (mostly `Already there`) | `Nothing to redo. Everything's already in place.` | reuses ADM-8 degraded | ADM-3 gate still applies |
| **ADM-G1 Deprovision** | last event or none | n/a (rendered, not run) | n/a | outcome + retained work | `couldn't read the result... won't guess` | n/a (app never triggers) |

---

## 13. Keyboard / VoiceOver (reused, extended for the two spine surfaces)

- **Sidebar** is a standard source list: Up/Down between items, section headers announced, selection drives the detail pane. Connect GitHub and Review & run take their reading-order positions; downstream items announce "not available yet" while the GitHub gate is unmet (VO reason carried in `accessibilityValue`).
- **ADM-3 refusal:** a VO group "GitHub access, not ready, and how to fix it"; the copyable `gh auth refresh...` command is `.textSelection(.enabled)` with a `Copy` affordance and a "Copied" confirmation; **Check again** is `.defaultAction`.
- **ADM-8 run:** the trigger is `.defaultAction` when enabled. Each resolving row is a **polite live region** announcing "step name, outcome" ("Created your organization space, created"; "Sales department, already there") so a VO operator hears each step land without focus theft. The summary count is a live region. A `Stopped`/`failed` row announces its owner and the fix; **Run again** is reachable.
- **ADM-9 rows:** each a VO element announcing "check name, status, owner"; status always in the label (never color/shape only); a red row's drill-in and `Go fix this` are focusable.
- **Configure forms:** `FocusState` chains top to bottom; Return submits the section primary; inline errors are announced on the offending field (`accessibilityValue` carries the message); the **secret-shape refusal is announced firmly**.
- **Handoff header** is a VO container announced on window open ("Handoff status: publisher done, next owner you").
- Reduce Motion: run rows cross-fade to their resolved word (no spring/pulse); the roadmap marker moves without spring.

---

## 14. Open questions for the owner (design-affecting; NOT resolved here)

These are the engine spec's own open decisions (`admin-agentic-setup.md` §5), surfaced where each one changes what the UI must render or gate. **Left open by design.**

1. **Interim engine home (engine §5.1).** Ship the vetted idempotent `gh` script (`scripts/admin_bootstrap.sh`) as the engine **now** (pre-WS-A), migrating into `copilot admin bootstrap --json` at freeze, **or** wait for the upstream verb before shipping any automation? *UI impact:* whether ADM-8 can render real streamed steps in the first build or must render a "not available yet, do it by hand" teach fallback. The run surface is designed to render the same `{step, result, detail}` from either home, so the seam is clean either way.
2. **WS-A scope (engine §5.2).** Fold `admin bootstrap [--add-department] [--verify] --json` into upstream WS-A alongside `publish`/`layers`, or keep it control-tower-originated? *UI impact:* none to the flow; it governs where the contract the app renders is frozen.
3. **`admin:org` acquisition (engine §5.3).** Teach `gh auth refresh -s admin:org` on the admin's own PAT, **or** stand up a GitHub App with fine-grained org-admin permissions? *UI impact: this changes ADM-3's refusal-fix copy and flow directly* — the PAT path teaches the exact `gh auth refresh` command (as drafted in §5); the GitHub App path replaces that with an install/authorize flow and adds App-private-key custody (which the shared store would home). ADM-3 must be authored against whichever is chosen.
4. **Fresh-repo seed delivery (engine §5.4).** On an empty `copilot-org`, initial-commit-then-protect (additive, since empty), switching to PR-only once the repo carries content, **or** PR-only from the start (chicken-and-egg on branch/CODEOWNERS)? *UI impact:* whether ADM-8 step 4 renders "Wrote your setup file" (initial commit) vs "Opened pull request #123" (PR) on a first run; the seed surface (ADM-6) already speaks "opens a pull request" for the content case.
5. **Integration classification (engine §5.5).** Which integrations the seed may declare as shared-store-backed vs. must-stay-personal (Salesforce/M365 shareable; anything acting as an individual identity must stay per-user)? *UI impact: this decides whether ADM-4's integration `id` is a constrained picker (safe) or free text (with only the secret-shape refusal guarding it).* Needed before operators classify their own integrations at each layer.
6. **`admin_capable` path 2a vs 2b (native-arch §6 / interaction-spec §5.1).** First-run opt-in ("I'm setting this up for my organization"), or always-available (every unmanaged user is their own admin)? *UI impact:* whether ADM-0's entry requires the Welcome-step declaration or Admin is simply always present in Settings. Both wire to the single `admin_capable` boolean, so the choice is one derivation, not a rework. Note: the OSS skill (ADM-SKILL) is a third, **un-gated** path regardless.

---

## 15. Invariant conformance

| Invariant | How this flow holds it |
|---|---|
| **#1 parse-never-compute** | The app collects inputs and renders streamed `{step, result, detail}` + `PreflightReport`; every existence check, idempotency decision, verdict, and leak-scan is the engine's. No `gh`/GitHub logic in Swift (§11). |
| **#3 never-destroy** | ADM-8 states the additive promise up front, renders `already-present` as calm/positive, and a re-run reads as `Already there` + `Nothing to redo`; add-department is a no-op re-run (§7, §9). |
| **#4 security inherited, not weakened** | ADM-3 refuses on missing scope/owner/auth and offers **only** the honest fix, never a `--skip-verify`/`--force`/bypass; the store config is read-only from signed inherited config (§5, §9). |
| **#5 route by competence** | The GitHub-owner / IT-infra / ENAC owners are named on refusals and Preflight reds; the operator drives their own org's standup; the user face never reaches any of it (§5, §8). |
| **#6 one-way inheritance, secrets never in git** | The secret-shape refusal blocks secrets from every configure field; the seed carries only `requires_secret` refs + the non-secret store endpoint; the step-5 leak-scan refuses to push a secret-shaped value; no write path to the personal tier (§6.3, §7.3). |

---

*Route to uids (Stage 3) for the visual system of the run checklist, the streamed-step marks, and the refusal styling; to cw for the `[cw]`-flagged new-surface strings (Connect GitHub refusals, Review & run trigger + outcome words + summary, the add-re-run governance line, the optional skill-path line); to ta for the contract items in §14 (the engine home, the streamed step schema, `admin_capable`, the handoff object). Every reused surface's copy is final in the copy deck Surface 3.*
