# Admin Experience: Service Design

|  |  |
|---|---|
| **Stage** | Service & experience design (sd) for **Admin mode**, post owner review (2026-07-10). Redesigns the current Admin flow (`control-tower-admin-flow.md`) against the owner's ratified verdict. Precedes interaction design (uxd). |
| **Deliverable** | A service blueprint plus journey narratives. **Design doc only.** No Swift, no HTML, no wireframes (those come next, from uxd). |
| **Persona** | **Earl**, a technical operator standing up his company's org on GitHub. End users (Bob) never see any of this. |
| **Reads on** | `CLAUDE.md` invariants (#1 parse-never-compute, #6 secrets-never-in-git govern everything here) · `docs/10-reference/copilot-solutioning-ecosystem.md` (CSE model) · `docs/10-reference/four-tier-topology.md` (inheritance, teams, read boundary) · `docs/03-design/admin-agentic-setup.md` (the engine: idempotent additive gh script / future `copilot admin bootstrap`) · `docs/03-design/control-tower-admin-flow.md` (the flow being redesigned) · `docs/03-design/control-tower-copy-deck.md` (voice) · `docs/03-design/three-role-journeys.md` §2 (Admin journey, labeled a HYPOTHESIS in §6). |
| **Evidence note** | The Admin journey is a **hypothesis**: no real operator has run it (three-role-journeys §6). Every pain point below is therefore labeled as a hypothesis or grounded in an analogous case (dev-tool CLI onboarding, gh auth flows, Terraform plan/apply), not field research. The single strongest recommendation this doc can make is to run the blueprint past one real operator before it hardens. |

---

## 0. Problem reframe, and the one concept decision that matters

### 0.1 The brief, reframed

The stated brief is "redesign the Admin-mode setup UI." The real job, read through JTBD:

> **When** I am told to stand up my company's copilots on GitHub, and I have never done it before, **I want to** describe my organization once and watch it become real and verified, **so I can** hand my team a working foundation without hand editing a config file, without creating a dozen repos by hand, and without ever being told to bypass a safety check.

The embedded assumption in the old design was that "the app sets up the org." The owner's verdict removes that: **the app does not fire GitHub mutations in v1.** Claude Code, running an open source skill over a deterministic idempotent script, does the work in the terminal. The app teaches, collects a description, hands off, and verifies against GitHub truth.

So the real design problem is not a wizard. It is a **baton pass**: app to Claude Code to app. That is the novel piece, and section 0.2 converges on it before anything else.

### 0.2 The baton pass: three framings, one selected

The app can detect local facts (is gh installed, is Claude Code installed) and can write a file or a command. It cannot and must not orchestrate a terminal session, and it must never trust a report from the terminal side. Given that, how do the app and Claude Code divide the work?

| HMW framing | Desirable | Feasible | Viable | Verdict |
|---|---|---|---|---|
| **HMW-1: How might we let the app fire the GitHub mutations, so Earl never leaves the GUI?** | High (one surface) | **Low** in v1: the verb is unbuilt; the app cannot absorb the mess Claude Code absorbs (gh missing, org not created yet, wrong scopes, partial prior runs); org creation categorically needs a human plus billing | **Low**: couples the app's release to an unbuilt engine, and re-implements conversationally what Claude Code already does better | **Rejected** by owner verdict and invariant #1 |
| **HMW-2: How might we let Claude Code drive while the app mirrors terminal progress live?** | Medium | **Low**: there is no safe, verifiable channel from the terminal; mirroring stdout means trusting a report the app cannot check, which is exactly the anti-pattern the brief forbids | **Low** | **Rejected**: the app is required to re-derive truth from GitHub, not to trust the terminal |
| **HMW-3: How might we make the app the confident briefer and honest verifier, and let Claude Code be the capable, mess-absorbing driver, so each does only what it is best and safest at?** | **High**: Earl gets a conversational driver that handles every mess AND an app that proves the result from GitHub truth | **High**: the app only detects local facts, writes a non-secret brief, and renders a read-only verify verb, all inside invariant #1 | **High**: decouples the app from the engine's readiness, reuses the OSS skill, keeps the app a thin skin | **Selected** |

**Selected: HMW-3.** Rationale: it is the only framing that honors invariant #1 (the app computes and mutates nothing), matches the owner verdict, and turns the app's blindness during execution from a weakness into an honest division of labor. The app owns **confidence before** and **truth after**. The terminal owns **capable execution**. The rejected framings both require the app to either do work it must not do (HMW-1) or trust a channel it must not trust (HMW-2).

**What this means for every stage below:** the app never streams `Created` / `Already there` rows of its own, because it fires nothing. That craft (the never-destroy legibility) does not die; it **relocates** to two honest homes: Claude Code's own narration in the terminal as the script runs, and the post-run Setup check, where a re-run against an already-standing org reads as a column of green with a plain count.

---

## 1. The service in one page

### 1.1 Actors

| Actor | Role in the service | Where it lives |
|---|---|---|
| **Earl (the admin)** | Describes the org, gets ready, hands off, verifies. Never hand edits a file. | The app window, then the terminal, then back to the app. |
| **The app (Control Tower, Admin mode)** | Teaches the arc, collects the org description into a non-secret brief, checks local readiness, generates the handoff, renders the Setup check. **Mutates nothing on GitHub.** | Native macOS window. |
| **Claude Code + the admin-bootstrap skill + the gh script** | The terminal actor. Reads the brief as its opening context, re-confirms with Earl, drives the deterministic idempotent additive standup. **The script, not the model, makes every check-then-act decision.** Absorbs mess conversationally. Refuses on missing scope; never bypasses. | Earl's terminal. |
| **GitHub** | The system of record. Holds the repos, teams, grants, and the org setup file. **The only user-management surface:** people join and leave by team membership here. | github.com and the org's repos. |
| **The shared secret store** | External service (Infisical / OpenBao class) that holds the org's keys and hands them out by team. Its endpoint travels in inherited org config; the keys never touch the app or any repo. | The store's own web UI, plus a reachable endpoint. |
| **Later: department authors and developers** | Build integrations (small CLI tools) from the owner's patterns, author department content. | Claude Code / Codex, in the department's repos. |
| **Later: end users (Bob)** | Install the user-face app themselves; it sets them up from what Earl built. Never see Admin mode. | Their own Mac. |

### 1.2 The three journeys

- **Journey A. Org standup (onboarding).** Describe, get ready, hand off, verify, invite. Done once, revisitable.
- **Journey B. Integrations lifecycle.** Understand, build (department engineer, in-repo), publish (registry manifest merged to main), discover and inherit, provision the secret, evolve or retire. The admin's role is education only; the app never declares or configures an integration.
- **Journey C. Governance steady-state.** Add a department or the second harness (safe re-run), handle a leaver (guidance, not management), connect a store if deferred, read the org setup, opt in to analytics.

### 1.3 Design principles (the eight that govern every decision here)

1. **Orientation before input.** The experience opens by explaining the whole arc before any field asks for anything. The old flow felt like a mystery because panels collected input before saying what it fed. No panel here collects before its purpose is on screen.
2. **The app teaches, collects, and verifies. It never mutates.** No gh call, no GitHub API call, no repo or team creation in Swift. Confidence before, truth after; execution belongs to the terminal.
3. **Refuse and teach.** When something is not ready, say what is true, name the one thing to do and its owner, and never offer a bypass, a `--force`, or a `--skip-verify`.
4. **Never-destroy, made legible.** The standup is additive and idempotent. Earl is told this up front, and a re-run visibly reads as "already there." Safe-to-run-again is answered before and after the fact.
5. **GitHub is the only user-management surface.** Onboarding creates structure (repos, teams, grants). People join and leave by team membership on GitHub. The app never manages people.
6. **Count, never score.** Verification is a plain count of what must be fixed and what could not be checked, each red naming its owner. No percentage, no gauge, no aggregate.
7. **No em-dashes** in any user-facing copy. Periods, commas, colons, parentheses only.
8. **No time estimates.** Name the phase, never a clock. No "a few minutes," no countdown, no percentage-as-promise.

### 1.4 Preserved craft from the current flow

The owner asked to keep what survives the restructure. These carry over verbatim in spirit: **refuse-and-teach** (relocated to Connect GitHub readiness and to Claude Code's terminal handling), **`Already there` as never-destroy made legible** (relocated to terminal narration and the Setup check re-run), **owner-named failures** (kept in the Setup check and in every refusal), **count-never-score** (kept in the Setup check).

---

## 2. Journey A: Org standup (onboarding)

The spine, stage by stage. For each stage: **Where** (app / terminal / github.com / store UI), **Frontstage** (what Earl sees and does), **Backstage** (what executes and what artifacts exist after), **Failure and recovery**, **Emotional beat**, and **Copy tone** with a few drafted lines in the air-traffic-controller voice.

### A0. Orientation (teach the ecosystem, then the arc)

Assume Earl knows nothing about the ecosystem. This surface has to teach what it is before it teaches what to do. Progressive disclosure keeps the main view calm and puts the depth behind a **Learn more** affordance.

- **Where:** app window, the first thing on open.
- **Frontstage (main view, calm):** three things, no fields.
  1. **What this builds, in one paragraph:** `Your copilots live in a set of shared spaces on GitHub that build on one another. The open-source foundation sits at the bottom. Your organization adds its own on top. Each department adds what only it needs. Each person adds their own on top of that. Everyone inherits everything beneath them, so your organization can share broad capabilities widely and keep specialized ones narrow.`
  2. **The whole arc, three read-only steps:** (1) Describe your organization here. (2) Claude Code sets it up in your terminal. (3) Come back and run the Setup check. Plus the plain assurance: `This app never changes anything on GitHub itself. It gets you ready, hands the work to Claude Code, and checks the result.`
  3. A **Learn more** affordance and the persistent handoff header (`Publisher done, Setup vX, Next: you`) above.
- **Frontstage (Learn more, deeper explainer views with theme-aware diagrams):** opening Learn more reveals two explainer views built around **theme-aware redraws of the owner's canonical ecosystem diagram** (`docs/10-reference/copilot-solutioning-ecosystem.svg`, redrawn so it is legible in light and dark, never a flat raster).
  - **View 1, "How the ecosystem works":** the inheritance diagram (foundation to org to department to personal, arrows showing each layer inheriting everything beneath it and adding its own), and the three kinds of space every layer carries: `one for instructions and agents (your development harness's copilot), one for knowledge (your company's information), and one for integrations (tools that reach outside systems).` It names what the org level itself carries: org-level agents, org-level integrations, and org information and knowledge (for example, your organizational structure and org-specific skill sets).
  - **View 2, "What your team gets" (the user benefit):** answers "how does this framework help people build their own solutions?" plainly: `Every person inherits your organization's agents, skills, knowledge, and integrations, plus their department's, on top of the open-source foundation. They build their own solutions faster and more consistently, because the shared capability is already there. They go broad with what the organization shares, narrow with what their department adds, and personal on top.` Concrete, ratified examples ground it:
    - **Org level:** a skill that writes on-brand documents in your brand voice, and a skill that builds proposals and statements of work.
    - **Accounting:** a month-end reconciliation skill that matches the general ledger to the bank and sub-ledgers, flags exceptions for a person to review, and drafts variance commentary.
    - **IT:** an onboarding and offboarding access-runbook skill.
    - **Sales:** a call-prep brief skill.
- **Backstage:** the app reads the Publisher to Admin handoff object and renders it (parse-never-compute). The diagrams are static explainer assets redrawn per theme; they render no live state. No mutation. The `admin_capable` fact governs whether this surface is reachable at all (exposure is the harm; absent, not disabled, when false).
- **Failure and recovery:** if the handoff object is unreadable, the header shows `Not started yet` and the app says `I couldn't read the result of this, so I won't guess.` It never fabricates a baton. The teach content and diagrams never depend on live state, so they always render.
- **Emotional beat:** Earl arrives knowing nothing and braced for "hand-edit YAML and create a pile of repos by hand." The main view converts that into cautious orientation in a few seconds; Learn more converts the curious operator into a confident one who understands why the repos exist and what his team gets. **This is a moment of truth:** the whole model either reads as sensible quickly, or Earl distrusts the split for the rest of the journey. The progressive disclosure protects both the hurried operator (calm main view) and the careful one (real depth on demand).
- **Copy tone:** calm and whole-picture on the surface, genuinely educational underneath. Teach the ecosystem in plain words and concrete skills, never abstractions.

### A1. Prerequisites and reality check

- **Where:** app window (teach only). The realities it names live on github.com and in billing.
- **Frontstage:** a short, honest checklist of what must be true before setup can run, none of it done here. Three facts: your organization exists on GitHub (creating one needs billing and a person, so it cannot be automated); you are an owner of it (only an owner can create the org's spaces); you have GitHub's command-line tool and Claude Code on this Mac (the next step checks and helps).
- **Backstage:** pure teach. No detection yet (detection is A2). The screen encodes the one categorical automation boundary: org creation is a human-plus-billing act at github.com.
- **Failure and recovery:** none to recover here; this stage exists precisely so nothing strands Earl halfway later. If the org does not exist yet, the honest instruction is to create it at github.com first, then return.
- **Emotional beat:** if the org already exists and Earl is an owner, competent confidence. If not, mild dread ("another thing that needs billing and a person"). Naming the boundary plainly (rather than letting the app fail on it later) is what keeps the dread from becoming a stranding.
- **Copy tone:** `A few things need to be true before setup can run. None of them happen here. This is so nothing stops you halfway. Your organization exists on GitHub. Creating one needs billing and a person, so it can't be automated. You are an owner of it. Only an owner can create the organization's spaces.`

### A2. Connect GitHub (local readiness, refuse-and-teach)

- **Where:** app window (local detection only). Fixes happen in Terminal and, for scope, through gh.
- **Frontstage:** the app checks that this Mac is ready for the terminal session, and changes nothing. It checks, as plain rows: is GitHub's command-line tool installed; is it signed in; is your account an owner of the org; does the sign-in carry the access setup needs; is Claude Code installed. Each not-ready row teaches the one fix and offers **Check again**. It never offers a bypass.
- **Backstage:** the app runs local, read-only detection (`gh auth status`, a version probe for gh and Claude Code, an owner and scope check). No mutation. Detection results are rendered, not computed into a verdict the app owns; the authoritative gate is the script, which re-checks in the terminal.
- **Failure and recovery (the load-bearing table):**

  | Not-ready reason | Rendered line (drafted, ATC voice) | Fix affordance |
  |---|---|---|
  | gh not installed | `GitHub's command-line tool isn't on this Mac yet. Setup runs through it.` | copyable `brew install gh`, plus a download link; then **Check again** |
  | gh not signed in | `You're not signed in to GitHub's command-line tool yet.` | copyable `gh auth login`; then **Check again** |
  | not an owner of the org | `Your GitHub account isn't an owner of this organization, so it can't create its spaces. Ask an owner to run this, or to make you one.` | names the **GitHub org owner** as the fix owner; **Check again** |
  | missing scope | `Your GitHub sign-in is missing the access setup needs.` | copyable `gh auth refresh -s admin:org -s repo`; then **Check again**. No bypass, ever. |
  | Claude Code not installed | `Claude Code isn't on this Mac yet. Setup runs there, so you'll want it before you hand off.` | install guidance; **Check again** |

- **Emotional beat:** the classic operator anxiety ("am I even allowed to do this"). Green readiness relieves it; a clear refusal with a named owner and an exact command is nearly as reassuring, because it converts "blocked" into "one known step." **Moment of truth:** whether a missing scope reads as a dead-end or as a copy-paste-and-continue.
- **Design decision (readiness, not a lock):** the app's readiness is **advisory and strongly guiding, not the enforcer.** The script re-checks everything and is the real gate; Claude Code absorbs anything still missing when the run starts. So the app should guide Earl to green before handing off, and say so, but the ultimate authority is the terminal. The exact firmness (soft-block the hand-off action, or merely warn) is an open question for the owner (section 7).
- **Copy note appended to the surface:** `Claude Code checks all of this again when setup runs, and helps you fix anything that's off. This step just gives you a head start.`

### A3. Describe your organization (teach, then the concrete plan)

- **Where:** app window (collect only). Nothing is created here.
- **Frontstage (teach first):** before the fields, a short plain purpose: `Departments get their own spaces so specialized capabilities are tailored to how that department actually works. Accounting's spaces hold Accounting's skills and knowledge, Sales's hold Sales's, and each department's people inherit the whole organization's on top.` And, prominent (not a footnote), the safety of going incremental: `You don't have to add every department now. Adding one later is safe. Setting up again only adds what's new and never touches what's already there.`
- **Frontstage (the one org-wide question, asked once): the development harness.** `Which development harness does your company build with?` with two choices, **Claude Code** or **Codex**. This determines whether the standup creates `claude-copilot-*` or `codex-copilot-*` spaces everywhere. Reassurance sits right under it: `This is your organization's default. Anyone can still use the other harness for themselves, on the open-source foundation plus their own personal setup. And you can add the second harness for the whole organization later, as a safe re-run that only adds what's new.`
- **Frontstage (identity, departments, and the live plan):** Earl types the organization's name and adds its departments. As he types, a **"What this will create"** card fills in with the exact, concrete plan, by real name, never an abstract summary. For `acme-co`, a Codex shop, with departments Accounting and Sales:
  - `Three shared spaces for your whole organization: acme-co/codex-copilot, acme-co/knowledge-copilot, acme-co/cli-copilot. Private.`
  - `Three spaces for the Accounting department: acme-co/codex-copilot-accounting, acme-co/knowledge-copilot-accounting, acme-co/cli-copilot-accounting. Private. An Accounting team that can reach them.`
  - `Three spaces for the Sales department: acme-co/codex-copilot-sales, acme-co/knowledge-copilot-sales, acme-co/cli-copilot-sales. Private. A Sales team that can reach them.`
  - `Your whole organization set to read by default.`
  The card repeats the add-later promise so it is present at the moment of decision.
- **Backstage:** the org slug, the harness choice, and the department list are validated (slugs as GitHub slugs) and written into the **non-secret standup brief** (section A6 defines the brief). The concrete names are derived by the same convention the script enforces: three spaces per layer, `<harness>-copilot`, `knowledge-copilot`, `cli-copilot` at org, each suffixed by `-<unit>` per department, where `<harness>` is the org's chosen `claude` or `codex`. The app derives the display names for legibility; the script is the authority that actually creates them.
- **Failure and recovery:** an invalid slug is refused inline with a plain message (`Give this department a name using letters, numbers, and dashes.`). No half-valid plan reaches the brief. The harness choice has a sensible default and can be changed until hand-off.
- **Emotional beat:** **the strongest positive moment of truth in the whole journey.** Seeing `acme-co/codex-copilot-accounting` and an `Accounting` team named on screen converts an abstract "set up my org" into something Earl can point at and trust. The harness reassurance defuses the "am I locking everyone into one tool forever?" worry before it forms. Abstraction is where operator confidence goes to die; concreteness is where it is won.
- **Copy tone:** `Tell setup your organization's name, the harness it builds with, and its departments. As you type, you'll see exactly what will be created. Nothing is created here. This is the plan setup will follow.`
- **Killed here:** the old members / team-grant sub-panel. Onboarding creates the team and the grant that makes joining possible; it never adds or removes the people. That is GitHub's surface (principle 5).

### A4. Integrations (education only; the admin never declares anything)

The correction here is total: **the admin does not declare integrations, ever.** At standup, no integrations exist. This surface teaches the model and previews how integrations will arrive later. It collects nothing.

- **Where:** app window (educate only). The building happens later in the department's repos; the key lives in the store; publishing happens on GitHub.
- **Frontstage (the education, kept):** the screen leads with the model, and this copy stays as authored: an integration here is a small command-line tool a developer builds so a copilot can reach a system (Salesforce, a calendar, an internal API). It is not a switch you flip. Then the cascade in plain words: something built and published for the whole organization is inherited by every department; something published for one department belongs only to that department; if it exists nowhere, it exists for no one. Then where the key lives: an integration names the key it needs; the key itself never comes near this app; it lives in the shared store, handed out only to the right team.
- **Frontstage ("How integrations will arrive," a lifecycle preview):** below the education, a plain read-only walk-through of the path an integration takes, so Earl knows what to expect and what to tell his people:
  1. `An engineer on a department builds skills, agents, and integrations inside that department's spaces.` (The advice to assign an engineer per department lives here, pointing at GitHub team write access: `Give an engineer write access to a department's team and they can build there.` The app never collects engineer names.)
  2. `Each integration is added to a registry, a plain document that lives in the same space and lists what has been built.`
  3. `Merging that document to the main copy publishes the integration.`
  4. `From then on, the people entitled to that space see it, and the app your team uses can let them know when a new one arrives.`
- **Frontstage (a small future-state mock of the registry view):** a quiet, clearly-labeled preview of what the published registry will look like once a department's engineer has built something, so the concept is concrete without pretending anything exists yet. It is a mock, marked as such.
- **Frontstage (the honest ending):** `There's nothing to set up here today. No integrations exist yet, and that's expected. They arrive when your departments' engineers build and publish them.`
- **Backstage:** none. This surface writes nothing to the brief and mutates nothing. Integration declarations have been removed from the org setup file entirely (see Journey B and A7): `ecosystem.yml` now carries components, departments, the harness choice, and the store pointer only. Absence-equals-non-existence has moved to the per-repo registries, still gated by entitlement (a user sees only the registries of the spaces they can reach).
- **Failure and recovery:** none to recover; there is no input. The registry mock is static.
- **Emotional beat:** an operator expecting a place to "turn on Salesforce" finds an explanation instead, and, done well, that is a relief, not a letdown: it tells Earl this is not his job to configure, it is his engineers' job to build, and the app will not pretend otherwise. The honest ending ("nothing to set up here today") is calming precisely because it does not manufacture busywork.
- **Copy tone:** `An integration here is a small command-line tool a developer builds, so a copilot can reach a system like Salesforce or your calendar. It isn't something you switch on. There's nothing to set up here today. Integrations arrive when your departments' engineers build and publish them.`

### A5. Secret store (educate, then connect or defer)

This supersedes "required." Because no integrations exist at standup (A4), a store is not needed to finish standup; it is needed before any shared integration can work. So this surface educates, then offers connect-or-defer honestly, without pretending a store is mandatory today or that shared integrations will work without one.

- **Where:** app window (educate and, if connecting, collect the endpoint and team mapping). The keys live in the store's own UI; the store is an external reachable service.
- **Frontstage (educate first):** lead with what a store is and why it exists, before any field. `A shared secret store is one service that holds your organization's keys and hands them out by team. Shared integrations need it: an integration names the key it needs, and at runtime the store checks that the person is on the right GitHub team and only then hands over the key. That is why a key never lives in a repo or in this app.`
- **Frontstage (connect):** if the org has a store, a short guided form: store type (picker), store address (a web address, validated on blur, helper text `This is a web address, not a secret.`), and which teams can use it (a team-to-scope mapping). No key is ever pasted here.
- **Frontstage (no store yet): connect-or-defer, both honest.**
  - The plain truth first: `Shared integrations can't work until you connect a store. You have no integrations yet, so you can finish setting up now and connect a store before your first one is built.`
  - **Pause and go get one:** named examples and a link out: `Common shared stores are 1Password, Infisical, and Vault (also called OpenBao). Set one up, then come back with its web address.` The app waits.
  - **Defer and finish standup:** an explicit, honest deferral (not a silent skip): `Skip this for now. You'll be reminded to connect a store before your first shared integration can work.` Deferring routes the connect step to its governance home (see below).
- **Backstage:** if connected, the endpoint URL and team-to-scope mapping go into the standup brief as the non-secret store pointer (the endpoint is not a secret; access stays gated at the store by the user's own GitHub-team membership). If deferred, the brief carries no store pointer and the org setup file simply has none yet. The secret-shape refusal guards every field either way.
- **Governance home for the deferred case (placement decision):** a **dedicated governance surface, "Connect the shared store,"** separate from the read-only Org setup summary (Journey C). Rationale: connecting a store is a **write** (it adds the store pointer to the org setup, authored by the script through the same hand-off), while Org setup is read-only by design; folding a write action into a read-only summary would break that surface's honesty. The governance surface reuses this exact educate-and-connect form, so there is one mental model whether the store is connected at standup or later.
- **Failure and recovery:** an address that is not a URL is refused (`That doesn't look like a valid address.`). A secret-shaped value is refused and not saved: `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.` If a connected store is unreachable, that surfaces honestly later in the Setup check (owner named as IT infra), never as a false green here.
- **Emotional beat:** if a store already exists, low-friction competence. If not, the honesty ("integrations can't work without one, and you have none yet") removes both the false wall of a hard requirement and the false comfort of a silent skip. **Moment of truth:** whether the no-store case reads as a trap or as a clear, deferrable choice with a named follow-up.
- **Copy tone:** `A shared secret store holds your organization's keys and hands them out by team. Your shared integrations will need it. You can connect one now, or finish setting up and connect one before your first integration is built.`

### A6. Review and hand off (the baton pass)

- **Where:** app window (assemble and generate). The next stage is the terminal.
- **Frontstage:** the final, concrete enumeration of everything the standup will create (the same real repo and team names from A3, plus the org setup file and the read-by-default change), topped by the never-destroy promise: `This adds and updates. It never deletes or overwrites anything already there.` Below it, the baton-pass explainer and the single copyable command:
  - `Setup runs in your terminal, with Claude Code. Copy the line below, open your terminal, and paste it. Claude Code will walk you through the rest and check everything with GitHub as it goes.`
  - a one-line copyable command, with **Copy** and a `Copied` confirmation, plus a secondary **Open Terminal**.
  - an honesty line about what crosses the boundary: `This hands Claude Code a plain description of your organization. It carries no secrets. Claude Code checks it with you, then does the work.`
  - the return instruction: `When Claude Code says it's done, come back here and run the Setup check.`
  The primary action is **Copy the setup command**, not "Set up my org." The app fires no mutation.
- **Backstage (what exactly crosses the boundary):** two artifacts, with a clear precedence:
  1. **The standup brief:** the app writes the collected org description to a known path as a non-secret **markdown file** (reviewable by Earl, readable by the app, and copy-and-pasteable): org slug, harness choice, department list, and (if connected) the store endpoint and team-to-scope mapping. It carries **no** integration declarations (there are none) and no secrets (every field passed the secret-shape refusal). This is how the org description reaches the skill.
  2. **The command:** a single copyable line that starts Claude Code with the admin-bootstrap skill pointed at that brief. Because the app orchestrates nothing in the terminal, this is a copy-to-clipboard convenience plus an Open Terminal helper.
  **The brief is a starting point, not a contract.** The skill reads it as opening context, re-confirms with Earl conversationally, and may diverge (Earl might add a department in conversation). GitHub truth wins; the Setup check reveals any drift (A8). The app never trusts a report from the terminal side.
- **Failure and recovery:** if the brief cannot be written (disk, permissions), the app says so plainly and offers to try again; it never hands off a command that points at a missing brief. If Earl prefers to skip the app's brief entirely and describe the org to Claude Code from scratch, that is a supported path (the skill can gather everything conversationally); the app's brief is a head start, not a gate.
- **Emotional beat:** anticipation, plus a flicker of "wait, I have to go to the terminal now?" The concrete enumeration and the framing of Claude Code as the capable, guiding driver reduce the surprise. Orientation (A0) already pre-empted it. **This is the pivotal moment of truth of the redesign:** the handoff either reads as a confident pass to a more capable teammate, or as being dropped.
- **Copy tone:** confident handoff, not abandonment. Name the driver, name the return, promise never-destroy.

### A7. Handed off (setup is running in the terminal)

- **Where:** the terminal (the real work). The app shows an honest blind resting state.
- **Frontstage in the terminal:** Claude Code, driven by the skill, narrates the standup as the script runs it: it re-confirms the plan, checks gh readiness (and guides any fix), then works down the ordered sequence, saying per step whether each space, team, grant, and the setup file was **created** or was **already there**, and refusing plainly if a scope is missing or the leak-scan finds a secret-shaped value in the setup file. This is where the streamed-outcome craft now lives, spoken conversationally rather than rendered as GUI rows. Because Claude Code converses, the categorical mess cases (gh missing, org not created yet, wrong scopes, a partial previous run) are absorbed in dialogue rather than met with a rigid refusal screen.
- **Frontstage in the app:** an honest resting state that does not pretend to see the terminal. `Setup is running in your terminal. Claude Code is setting up your organization now. This app can't see your terminal, so it won't guess how it's going. When Claude Code says it's done, run the Setup check and this app will read the result straight from GitHub.` A single action: **Run the Setup check.** A reassurance that nothing is lost on close: `Your organization's setup lives on GitHub, and the Setup check reads it fresh every time.`
- **Backstage:** the script executes the ordered, idempotent, additive GitHub sequence (org read-by-default; create the three org spaces named by the chosen harness; per department create the three spaces, the team, and the grant that is the entitlement; write the org setup file additively; fail-closed leak-scan before any push; leave verification to the Setup check). The script, not the model, makes every check-then-act decision. Artifacts afterward: the repos, teams, grants, the org read-by-default setting, and the org setup file (`ecosystem.yml`), written once, living forever, as the config-of-record every user's copilot CLI reads. In this model `ecosystem.yml` carries **components, departments, the harness choice, and the store pointer only** (no integration declarations; those live in the per-repo registries and arrive via Journey B).
- **Failure and recovery:** the script never leaves a half-created state a re-run cannot safely reconcile (additive, idempotent). If it refuses (missing scope, or a secret-shaped value in the setup file), Claude Code says so plainly, Earl fixes it, and re-runs; already-done steps narrate as already-there. The app, being blind by design, adds nothing here except the honest "come back and check" state.
- **Emotional beat:** this is where the app goes dark, and the design risk is abandonment ("did it work?"). Two things carry it: the terminal itself is reassuring because Claude Code is talking and absorbing every mess, which is often calmer than a rigid GUI that refuses; and orientation set this expectation up front. The tension resolves at the reunion (A8).
- **Copy tone:** honest about blindness, never a fake spinner. The app admits what it cannot see and points at the one true way to know.

### A8. Setup check (post-run verification, from GitHub truth)

- **Where:** app window (render). The truth being read lives on GitHub and at the store.
- **Frontstage:** an honest red and green list of what is really on GitHub now, one row per check, each red naming who has to fix it. Rows: the org's three spaces exist and the org is read-by-default; each department's three spaces exist; each department team can reach its spaces; the org setup file reads cleanly; the store answers. Summary is a plain count, never a score: `2 things must be fixed. 1 couldn't be checked.` and, when clean, `Everything's ready to hand over.` A drift note: `This reads GitHub, not what you typed. If setup did more or less than the plan, you'll see it here.`
- **Backstage:** the app shells a **read-only verify verb** (the script's verify mode, or `copilot admin bootstrap --verify --json`) that reads GitHub truth and the store's reachability and emits `{check, status, detail, owner}` rows. The app renders; it computes no verdict. `unknown` is rendered distinctly and never green (fail-closed). Owners named: **Admin** for repos and grants, **GitHub org owner** for base permission, **IT infra** for the store, **ENAC / external** for the foundation reference.
- **How drift is handled (GitHub truth wins):** the verify verb compares what the brief declared (org, harness, departments, and, if set, the store pointer) against GitHub truth. A thing the brief declared and GitHub is missing is red (Admin owns it). A thing present on GitHub beyond the brief (Earl added a department in conversation, or set up the other harness's spaces too) is shown as present, not an error, because the standup is additive and GitHub is authoritative. Disagreement is rendered plainly, with GitHub labeled as the source. This satisfies "GitHub truth wins; the Setup check reveals drift" without the app computing anything.
- **Failure and recovery:** a check that itself errors renders `unknown` with an honest reason, never green, never a crash. An Admin-owned red offers `Go fix this`, jumping to the surface that authored the offending input; a re-run is always available and, against an already-standing org, reads as a column of green (never-destroy made legible, relocated here).
- **Emotional beat:** the reunion. Honest green is earned trust, because Earl can see it came from GitHub, not from a claim the terminal made. A red with a named owner is actionable, not a dead-end. This is the payoff that makes the blind handoff (A7) tolerable.
- **Copy tone:** honest verdict, plain count, owner on every red. `An honest look at what's really on GitHub now. Every red names who has to fix it.`

### A9. Done, and what now

- **Where:** app window, pointing outward to GitHub and to the user-face app.
- **Frontstage:** a calm confirmation (not a celebration) that the spaces exist, the teams can reach them, and the setup file is in place, followed by the two things Earl actually needs next:
  - **Invite the team, on GitHub:** `People join a department by being added to its team on GitHub. Add someone to the Sales team and they can join Sales from their own copilot. This app never manages people. GitHub does.`
  - **Point users at the user-face app:** `Your team installs Copilot Control Tower themselves, and it sets them up from what you just built. Send them the app, and they'll see the departments they're on.`
- **Backstage:** none. Pure render, plus deep links out to the org's teams on github.com.
- **Failure and recovery:** none; this stage only points outward.
- **Emotional beat:** quiet competence. The reward is not a trophy screen; it is being able to do the next real thing (invite people, hand out the app) with confidence.
- **Copy tone:** understated, forward-looking, no green-checkmark reward.

### A10. Acceptance signals for Journey A

- Every stage explains its purpose before it collects (orientation-before-input holds end to end); Orientation teaches the ecosystem, not just the arc.
- The harness is asked once, org-wide, and drives the whole naming (`claude-copilot-*` or `codex-copilot-*`), with the personal-use and add-later reassurance present at the point of choice.
- The concrete plan (A3) and the review (A6) name real repos and teams, never an abstract summary.
- Integrations collects nothing: the admin never declares an integration, and the surface ends honestly with "nothing to set up here today."
- The secret store educates and offers connect-or-defer honestly (no false "required," no silent skip); the deferred case has a named governance home.
- The app fires zero GitHub mutations across the whole journey (grep the render seam: no gh call in Swift).
- The Setup check verdict is re-derived from GitHub truth and reveals drift; a re-run reads as green.

---

## 3. Journey B: Integrations lifecycle

The admin's role in this journey is **education only.** Integrations are built and published by department engineers, in the departments' own repos; the app never declares, collects, or configures one. The engine (and the org setup file) know nothing about specific integrations; existence lives in per-repo registries, gated by entitlement.

| Phase | What happens | Where | The admin's / app's role |
|---|---|---|---|
| **Understand** | An admin (or an engineer) learns that an integration here is a small CLI tool a developer builds, not a native switch; that it names a key but never carries one; that existence is a published registry entry, gated by who can reach the repo. | App (the A4 education surface). | **Education only.** The app teaches the model and previews the lifecycle. It collects nothing. |
| **Build (department engineer, in-repo)** | An engineer with write access to a department's team builds skills, agents, and the integration inside that department's spaces, using the org's harness (Claude Code or Codex) and the owner's published patterns and templates. | The department's repos (for example `acme-co/cli-copilot-accounting`), in Claude Code / Codex. | **Outside the app.** The app's copy advises assigning an engineer per department and points at GitHub team write access; it never collects engineer names. |
| **Publish (registry manifest, merged to main)** | The engineer adds the integration to a registry manifest (a JSON-style document that lives in the repo and lists what has been built), and merging it to main publishes the integration. | The department's repo on GitHub (the registry document plus a merge to main). | **Renders the concept** (the A4 lifecycle preview and the registry mock). It does not perform the merge. |
| **Discover / inherit** | Entitled users' machines resolve the union of the registries across the spaces they can reach; the user-face app renders what is available and can notify when a new one arrives. Something published for the org is inherited by every department; something published for a department belongs to that department; anything published nowhere exists for no one. | The resolver plus the user-face app on each user's machine. | **Not the admin's surface.** This is the user experience; the admin's app renders that registries exist, in the read-only Org setup summary. |
| **Provision the secret (via the store)** | The named key is placed in the shared store, scoped to the team that should reach it. At runtime the store checks GitHub-team membership and hands over the key; users never set up their own key for a shared integration. | The store's own UI (plus the store pointer set in A5 or its governance surface). | **Never touches the key.** The store hands it out by entitlement; the value lives only in the store. |
| **Evolve / retire** | Changing an integration is editing its registry entry and re-merging; retiring one is removing its registry entry and rotating its key in the store. | The department's repo (registry edit and merge) plus the store's UI (key rotation). | **Renders** what exists now; every change is an in-repo edit plus a store action, never an in-app mutation. |

**Consequence for the engine and the org setup file:** `ecosystem.yml` no longer carries integration declarations at all. It holds components, departments, the harness choice, and the store pointer only. **Absence-equals-non-existence now lives in the per-repo registries**, still gated by entitlement: a user sees only the registries of the repos they can reach, so an unpublished (or unentitled) integration is invisible, exactly as before, just relocated from a central declaration to distributed registries.

**Emotional arc for Journey B:** the risk is an operator expecting an "integrations marketplace" to configure and finding an authoring-and-publishing model instead. The education-first framing reframes the expectation: integrations are things your engineers build and publish in the departments, not a catalog you shop or a list you maintain. Relief comes from realizing this is not the admin's burden, and from the inheritance rule (build once for the org, everyone inherits).

**What Journey B is NOT:** there is no integrations tab, no config surface, no declaration act, no catalog to toggle, and no admin-maintained list. The app teaches the model and renders that registries exist; it never manages integrations.

---

## 4. Journey C: Governance steady-state

Occasional, calm, and mostly instructional. The same describe-hand off-verify instrument as standup, plus guidance for the acts that belong on GitHub and in the store.

### C1. Add a department, or the second harness (safe re-run)

- **Where:** app to describe the addition, terminal to run, app to verify.
- **Frontstage:** Earl returns to Describe your organization and adds the new department (for example, adding IT to acme-co), sees the concrete plan for just that unit's three spaces and its team, and hands off again. The governance entry frames it plainly: `Add a department here. Setting up again only adds what's new and never touches what's already there.` The same safe re-run also covers adding the org's second harness later: choosing to add Claude Code alongside Codex creates the `claude-copilot-*` spaces additively, leaving everything else untouched.
- **Backstage:** the same idempotent script runs; everything already present narrates as already-there; only the new unit's spaces, team, grant, and its setup-file entry (or the second harness's spaces) are created. The Setup check afterward reads as green for the existing org and green for the addition.
- **Emotional beat:** the fear is "will re-running break what already works?" The additive, already-there narration and the green re-run answer it before and after. This is never-destroy made legible in steady state.

### C2. Someone left (instructional guidance, not management)

- **Where:** the acts happen on GitHub (team removal) and in the store's UI (key rotation). The app only guides.
- **Frontstage:** `This app doesn't manage people. When someone leaves, remove them from their teams on GitHub. Then rotate the keys those teams could reach in your shared store, so their old access is worthless.` The app renders, read-only, the teams that person was on and the named keys tied to those teams (from the org setup), so Earl knows exactly what to rotate. There is no in-app "offboard" button, no device wipe, no remote action.
- **Backstage:** the app reads the person's team membership and, to name the keys to rotate, reads the registries of the spaces those teams could reach (registries name the required keys) together with the store's team-to-scope mapping. It triggers nothing. Content already on a departed person's disk is not remotely wiped (accepted residual; the guarantee is revoked access plus rotated keys, which make old copies worthless).
- **Emotional beat:** an operator used to a "deprovision" button may reach for one and find guidance instead. The honesty is the point: the app cannot and should not reach into GitHub or the store to remove a person, so it names exactly what to do and where, and lists the keys to rotate so nothing is missed.
- **This replaces** the old ADM-G1 "Deprovision" render (which rendered a revocation-and-rotation outcome). The owner's verdict makes it guidance: the app tells Earl to act on GitHub and in the store, and helps by naming the teams and the keys.

### C3. Connect the shared store (the deferred case)

- **Where:** app window (educate and collect the endpoint and team mapping); the store itself is external.
- **Frontstage:** the exact educate-and-connect form from A5, reachable in governance for the org that deferred at standup, or that is adding a store before its first integration ships. `Connect the store that holds your organization's shared keys. Your integrations will need it before they can work.`
- **Backstage:** collects the store type, address, and team-to-scope mapping (secret-shape refusal on every field), then hands off to the script (the same baton pass), which adds the store pointer to the org setup file additively. The app authors nothing directly.
- **Placement rationale (stated once):** this is its **own governance surface**, deliberately separate from the read-only Org setup summary (C4), because connecting a store is a write and the summary is read-only by design. Folding a write into a read-only view would break that surface's honesty; a dedicated surface reuses A5's form and keeps one mental model.

### C4. Org setup (read-only summary)

- **Where:** app window (render only). The truth lives in the org's setup file on GitHub and in the departments' registries.
- **Frontstage:** everything the organization hands out, in one read-only place: its copilots, the harness it builds with, their versions, its departments, where its shared keys come from (the store address), and, read from the departments' registries, the integrations that have been published. `This comes from your organization's setup on GitHub. It isn't editable here, by design.`
- **Backstage:** renders the parsed org setup file (components, harness, departments, versions, store pointer), the inherited store endpoint, and a read-only roll-up of the per-repo registries. Nothing is editable; security-sensitive config is honored only from inherited org config, never re-pointed from the app (invariant #4).
- **This merges** the old "Secret store config" governance panel into this single read-only summary, as the owner directed.

### C5. Analytics (off by default)

- **Where:** app window.
- **Frontstage:** a plain switch, off by default, with a read-only "What this would share." `Off. Nothing is shared unless you turn this on and your organization signs off on it.` No dark pattern.

### C6. What governance no longer contains

Stated explicitly, because the removals are the design:

- **No user management.** No members panel, no add/offboard control that touches people. People join and leave via GitHub teams (principle 5).
- **No policy signing.** Deferred entirely from v1. No panel, no user-facing concept. V1 relies on GitHub protections (private repos, branch protection, required reviews) that the script configures automatically.
- **No integration management.** No declaration act, no catalog, no admin-maintained list. Integrations are built and published by department engineers (Journey B); governance only renders what their registries have published.
- **No store editing.** Connecting a store (C3) is a deliberate, additive write authored by the script through the hand-off; the store endpoint shown in the Org setup summary is read-only and inherited, and is never re-pointed from local user config (invariant #4).

---

## 5. Screen inventory for uxd

The definitive list of surfaces the journeys imply. Per surface: purpose, collect vs render (invariant #1), key states including refusals, and the journey stage served. This is the input for wireframes and HTML mockups.

**App surfaces (16).** The terminal (Claude Code) and the store's own UI are non-app surfaces in the blueprint, listed after.

| # | Surface | Purpose | Collects / Renders | Key states (incl. refusals) | Serves |
|---|---|---|---|---|---|
| 1 | **Orientation** | Teach the ecosystem (what it is, inheritance, repo types, the user benefit) and then the whole arc; progressive disclosure. | Renders the arc, the handoff object, and (behind Learn more) two explainer views with theme-aware diagrams and concrete skill examples. Collects nothing. | main view (calm); Learn-more explainer view 1 (how it works) and view 2 (what the team gets); handoff-unreadable (`won't guess`, header `Not started yet`); teach content always renders. | A0 |
| 2 | **Prerequisites and reality check** | Teach what must be true first (org exists, owner, billing reality, tools present). | Renders a teach checklist. Collects nothing. | idle; not-started. | A1 |
| 3 | **Contacts** | Record who owns this setup (feeds the handoff header and Setup check owners). | Collects publisher / admin / point-of-contact names. | empty; saved. (Kept slim; this is metadata, not user management.) | A1 support |
| 4 | **Connect GitHub (readiness)** | Detect local readiness for the terminal session; refuse-and-teach. | Renders detection results; collects the org name and a check intent. No mutation. | idle (`Not checked yet`); working (`Checking...`, no ETA); ready; five refusal states (gh missing, not signed in, not owner, missing scope, Claude Code missing), each with the exact fix and **Check again**, no bypass; degraded (check could not run, honest). | A2 |
| 5 | **Describe your organization** | Teach why departments get their own spaces; ask the harness once, org-wide; collect identity and departments; show the concrete plan by real name. | Collects the harness choice, org slug, and department list. Renders the teach layer, the add-later promise, and the "What this will create" plan. | teach + harness choice (with personal-use / add-later reassurance); empty; typing (plan fills live, named by chosen harness); invalid-slug refusal (inline). | A3, C1 |
| 6 | **Integrations** | Education only: teach the model and preview how integrations will arrive. The admin declares nothing. | Renders the education copy, the "How integrations will arrive" lifecycle preview, a future-state registry mock, and the honest "nothing to set up today." **Collects nothing.** | education; lifecycle preview; registry mock (labeled as a mock); honest empty ending. No inputs, no refusals. | A4, B (educate) |
| 7 | **Secret store** | Educate on what a store is and its runtime use, then connect or defer honestly. | Collects (if connecting) store type, address, team-to-scope mapping. Renders the education, the connect form, and the no-store choice. | educate; connect (form); no-store: pause-and-go-get (named examples) or defer-and-finish; address-invalid refusal; secret-shape refusal; connected. | A5 |
| 8 | **Review and hand off** | Enumerate concretely what will be created; write the brief; generate the copyable command; frame the baton pass. | Renders the final plan and the never-destroy promise; collects the copy action. Writes the non-secret brief. | idle (plan + command + Copy); copied; brief-write failure (retry); Open Terminal. **No "set up my org" mutation.** | A6 |
| 9 | **Handed off (terminal in progress)** | Honest blind resting state while the terminal works; the one way back. | Renders an honest "can't see the terminal" state. Collects the intent to verify. | resting (`Run the Setup check`); close-safe reassurance. | A7 |
| 10 | **Setup check** | Post-run verification from GitHub truth; red/green, owner-named, count-never-score; reveal drift. | Renders `{check, status, detail, owner}` rows and a plain count. Computes no verdict. | empty (never run); working (rows fill, no ETA); done (count + owners); `unknown` (never green); Admin-red `Go fix this`; re-run reads green. | A8, C1 verify |
| 11 | **Done, and what now** | Confirm calmly; point to inviting via GitHub and to the user-face app. | Renders next steps and deep links out. Collects nothing. | done. | A9 |
| 12 | **Governance home / Add a department (or second harness)** | Entry to steady-state; frame the safe re-run. | Routes into Describe (5) for the new unit or the second harness. | idle; re-run reuses 5, 8, 9, 10. | C1 |
| 13 | **Someone left** | Instructional guidance for a leaver; render teams and the named keys to rotate. | Renders the person's teams and the keys tied to them (from registries + store mapping). Triggers nothing. | idle; render (teams + keys); unreadable (`won't guess`). No offboard button. | C2 |
| 14 | **Connect the shared store** | The deferred / governance home for connecting a store; reuses the A5 educate-and-connect form. | Collects store type, address, team-to-scope mapping, then hands off to the script. | educate; connect (form); secret-shape refusal; connected via hand-off. | C3 |
| 15 | **Org setup (read-only summary)** | Show everything the org distributes; assert it is inherited and not editable here. | Renders the parsed org setup (components, harness, departments, versions, store pointer) and a read-only roll-up of the departments' published integrations. Collects nothing. | render; not-editable note. (Merges the old store-config panel.) | C4 |
| 16 | **Analytics** | Off-by-default usage data with a read-only "what would share." | Collects the opt-in switch. Renders what would be sent. | off (default); on; what-would-share. | C5 |

**Non-app surfaces in the blueprint (for uxd's context, not to be designed as app screens):**

- **Terminal / Claude Code:** where the standup actually runs; where the streamed created / already-there narration and mess-absorption live. uxd should design the app's handoff and return to frame this well, not the terminal itself.
- **The store's own UI:** where keys are placed and rotated. The app links out; it never renders key values.
- **github.com:** where people are added to and removed from teams (the only user-management surface), and where the org must first be created.

**Killed surfaces (were in the current build, now absent):** the members / team-grant sub-panel, the integration declaration act (the admin declares nothing), the Seed YAML generator form, Policy signers, the app-fires-and-streams Review & run, the Deprovision render (now instructional), and the standalone Secret store config panel (merged into Org setup).

---

## 6. Deltas from the current build

For the developer reconciling `native/admin.swift` later. Current surface, disposition, and why.

| Current surface (admin-flow / admin.swift) | Disposition | Why |
|---|---|---|
| ADM-0 Entry / handoff | **Restructure and deepen** into **Orientation** | Orientation-before-input, now teaching the ecosystem itself (what it is, inheritance, repo types, the user benefit) via progressive disclosure: a calm main view plus Learn-more explainer views with theme-aware diagrams and concrete skill examples. The handoff header survives inside it. |
| ADM-1 Prerequisites | **Keep, reframe** | Add the billing-plus-owner reality and "the org must exist on github.com first" up front, as the categorical automation boundary. |
| ADM-2 Contacts | **Keep, slim** | Still feeds the handoff header and Setup check owner names. It is owner metadata, not user management, so it survives. |
| ADM-3 Connect GitHub | **Keep, extend** | Now also detects the gh CLI and guides install (brew or download), and detects Claude Code. Reframed as local readiness for the terminal session, advisory not enforcing (the script is the real gate). Refuse-and-teach retained; no bypass. |
| ADM-4 Departments & access (org id + departments) | **Restructure and extend** into **Describe your organization** | Adds the teach layer (why departments get their own spaces) and the org-wide **harness choice** (Claude Code or Codex), which drives the naming everywhere. Concrete "what this will create" plan by real repo and team name (never an abstract summary). Add-later safety made prominent. |
| ADM-4 members / team-grant sub-panel | **Kill** | GitHub is the only user-management surface. Onboarding creates the team and the grant; it never adds or removes people. |
| ADM-4 integration-per-layer declaration | **Restructure into education-only Integrations; kill the declaration act** | The admin never declares an integration. The surface teaches the model, previews how integrations arrive (engineer builds in-repo, registry manifest merged to main publishes, entitled users discover), shows a registry mock, and ends honestly with "nothing to set up today." Integration declarations leave `ecosystem.yml` entirely; existence lives in per-repo registries. |
| ADM-5 Secret store | **Keep, restructure** | Educate first (what a store is, its runtime team-membership check), then **connect-or-defer** (supersedes "required," since no integrations exist at standup): connect now, pause to go get one (1Password, Infisical, Vault/OpenBao), or defer and finish. Deferred connect gets its own governance home. Secret-shape refusal retained. |
| ADM-6 Seed generator (YAML form) | **Kill as a form** | The script writes `ecosystem.yml` from the brief. The seed is demystified in Orientation (config-of-record every user's CLI reads, written once, lives forever) and shown concretely in Review, not authored in a YAML form. |
| ADM-7 Policy signers | **Kill** | Policy signing deferred entirely from v1. No panel, no concept. V1 relies on GitHub protections the script configures. |
| ADM-8 Review & run (app fires bootstrap, streams rows) | **Restructure** into **Review and hand off** | The app fires no mutation and streams nothing. It enumerates concretely, writes the non-secret brief, generates the copyable command, and frames the baton pass. The streamed created / already-there craft relocates to Claude Code's terminal narration. |
| (new) | **Add: Handed off (terminal in progress)** | An honest blind resting state while the terminal works. The app admits it cannot see the terminal and points at the one way back. |
| ADM-9 Preflight | **Rename** to **Setup check** | The aviation name confused. It stays post-run verification from GitHub truth, red/green, owner-named, count-never-score, plus a drift note (GitHub truth wins). |
| (new) | **Add: Done, and what now** | Invite the team via GitHub; point users at the user-face app. |
| ADM-G1 Add / offboard (add path) | **Keep** as **Add a department** | A safe re-run; mostly already-there. Framed as never-destroy in steady state. |
| ADM-G1 Deprovision (render) | **Restructure** into **Someone left** (instructional) | Guidance, not management: remove them from GitHub teams, then rotate the named keys those teams could reach. The app renders teams and keys; it triggers nothing. |
| (new) | **Add: Connect the shared store (governance)** | The deferred / later home for connecting a store, reusing the A5 educate-and-connect form and handing off to the script. Its own surface, not folded into Org setup, because connecting is a write and Org setup is read-only. |
| ADM-G3 Secret store config | **Merge** into **Org setup (read-only summary)** | One read-only place for everything the org distributes: copilots, harness, versions, departments, the published integrations (rolled up from registries), and the store address. Inherited, not editable here. |
| ADM-G2 Analytics | **Keep** | Off by default, unchanged. |
| ADM-SKILL (an alternative path) | **Elevate** to the execution path | The terminal is no longer an "alternative." It is where the standup runs. The app is the face for teach and verify; Claude Code plus the skill plus the script is the execution engine. |
| `allScreensUnlockedForReview = true` (admin.swift:63) | **Unchanged concern** | Still a review-only bypass of the readiness gate; out of scope for this design, flagged for the developer to restore before real use. |

---

## 7. Open questions for the owner

Short by design. None reopen the ratified decisions (component-first naming with the org-wide harness choice, Claude-Code-leads execution, signing deferred, admin declares no integrations, store connect-or-defer).

1. **Where does `ecosystem.yml` live among the three org repos?** Working assumption: the org's **instruction-layer component repo** (`claude-copilot` or `codex-copilot`, per the chosen harness), as the home every user inherits. The CLI resolver contract should confirm the canonical path the copilot CLI reads. (TA / CLI-contract detail, not a service-design decision.)
A: Yes. The org-level component repo. 
2. **The exact shape of the copyable handoff command,** and the on-disk path and lifecycle of the standup brief. Depends on how the OSS skill is invoked from a shell and where the brief is written and whether it persists (a persisted brief gives the Setup check a clean "expected set" baseline for drift). A TA question that lightly affects the Review surface's copy.
A: I would assume a markdown file that is saved on the machine that can be reviewed, used by the app, or copy and pasted. 
3. **How firm is Connect GitHub's readiness?** Recommended: advisory and strongly guiding, not a hard block on the hand-off action, because the script is the real gate and Claude Code absorbs anything still missing. Owner to confirm the exact firmness (soft-block versus warn).
A: Your recommendation is good. 
4. **Version pins in v1.** Working assumption: the script applies a sensible foundation pin and Earl does not choose versions in the first cut. Confirm no per-org version selection is needed for v1.
A: Your understandingis correct. 
5. **Validation.** The Admin journey remains a hypothesis (three-role-journeys §6). The single highest-value next step is to run this blueprint past one real operator before it hardens, focusing on the baton pass (A6 to A8), which is the novel, untested moment.
A: Correct. 

---

*Route to uxd for the interaction design and wireframes of these 16 surfaces (the Orientation Learn-more explainer views with theme-aware ecosystem diagrams, the concrete-plan card in Describe, the Integrations lifecycle preview and registry mock, the Review-and-hand-off command block, the honest Handed-off resting state, and the Setup-check drift note are the novel pieces without a current-build precedent). Route to cw for the drafted strings above (the Orientation teach copy, the harness choice and its reassurance, the Integrations education and honest ending, the secret-store connect-or-defer copy, the baton-pass copy, the Someone-left guidance) to be finalized in the copy deck. Route to ta for the open-question contract items: the markdown brief's path and shape, the copyable command, the verify verb's drift comparison, the per-repo registry manifest format, and where `ecosystem.yml` lives.*
