# Copilot Control Tower: Copy Deck

Final UX copy for the native macOS app, organized by surface and state so an
implementer can drop each string straight into `native/*.swift`. This deck is the
`cw` (copywriting) deliverable the interaction spec closes on
(`control-tower-interaction-spec.md` §8: "route to cw for final microcopy of every
placeholder string herein").

**Ground truth read first:** `SOUL.md` (§7 Voice & Tone), the interaction spec, and
`docs/reference/cse-alignment-decisions.md` (the vocabulary).

## The voice, in one paragraph

Control Tower is an air-traffic controller: calm, factual, unhurried. It states what
is true and the one thing to do about it, then stops. When everything is fine, it is
silent. It writes for **Bob**, a change-averse, non-technical person who should never
have to learn a terminal, and it never blames him. It names the copilot that needs
something ("Codex Copilot needs you to sign in"), never a blur ("Something needs your
attention"). It speaks in the past tense for anything it already handled ("kept your
working version"). It never celebrates being healthy, never fabricates a state it
cannot prove, and never shows a raw error.

## Hard rules that shape every string here

1. **No em-dashes anywhere.** Periods, commas, colons, and parentheses only.
2. **Plain language.** No terms Bob would not use in conversation. No "MDM", no
   "repo" on a user surface where it can be avoided, no "entitled" as a bare word.
3. **"Copilot" and "component", never "product".** The four are **Claude Copilot,
   CLI Copilot, Codex Copilot, Knowledge Copilot**. "Product" means a built output
   (Insights, Pipeline, Method) and never appears in the app.
4. **The four layers** read as **foundation, org, department, personal**. To Bob,
   prefer "your organization", "your department", "this Mac", "your team".
5. **Active voice.** A button says exactly what it does ("Sign in to Slack", not "OK").
6. **Never fake-healthy.** Silence is the success state; there is no green checkmark
   reward, no "All good!" toast.
7. **No time, ever.** No "about 2 minutes left", no countdown, no percentage as a
   promise. Name the phase, not a clock.
8. **Names the owner of a fix.** IT-owned, network-owned, or the user's own thing,
   said plainly, never "failed, contact support".

---

# SURFACE 1: The menu-bar popover (S1)

## 1.1 Region 1: the status header sentence (one honest line per state)

`HeaderView.sentence`, rendered verbatim with the worst-wins glyph to its left. This is
the single most-read string in the product. It answers "is it OK, and do I have to do
anything?" in half a second.

| State | Glyph | Status sentence | Secondary line (host, quiet) |
|---|---|---|---|
| **current / healthy** | none | `Everything is set up.` | `This Mac` |
| **join-available** (tray stays calm) | none | `Everything on this Mac is set up.` | `This Mac` |
| **setup-needed** | hollow | `Let's finish setting you up.` | `This Mac` |
| **it-config-incomplete** | wrench | `CLI Copilot is waiting on setup from your organization.` (names the copilot) | `This Mac` |
| **waiting-for-network** | clock | `Waiting for the network.` | `This Mac` |
| **offline** | cloud-slash | `You're offline. I'll pick up where I left off when you're back.` | `This Mac` |
| **syncing** | ring | `Bringing everything up to date...` | `This Mac` |
| **signed-out** | key | `Codex Copilot needs you to sign in. Everything else is fine.` (names the copilot) | `This Mac` |
| **update-available** | update | `An update is ready. I'll install it quietly.` | `This Mac` |
| **needs-attention** | triangle | `Knowledge Copilot needs attention in your department.` (names copilot + layer + need) | `This Mac` |
| **updating-app** | spinner | `Updating Control Tower...` | `This Mac` |
| **cli-unreadable** | bang | `I can't read your setup right now, so I won't guess.` | (no host line) |

**Sentence-assembly patterns** (for the states the CLI fills in dynamically):

- **it-config-incomplete:** `<Copilot> is waiting on setup from your organization.`
  If more than one: `Some copilots are waiting on setup from your organization.`
- **signed-out:** `<Copilot> needs you to sign in. Everything else is fine.`
  If nothing else exists to reassure: `<Copilot> needs you to sign in.`
- **needs-attention:** `<Copilot> needs attention in your <layer-in-plain-words>.`
  Plain layer words: foundation = "core setup", org = "organization", department =
  "department", personal = "personal setup".

## 1.2 The cli-unreadable sentence, by reason ("versions don't match" and its siblings)

The `bang` state is the honest degrade. One plain sentence, no tree, no join row, retry
only. `cli_unreadable_reason` selects the variant; **the reason token is never shown**,
and no raw error text ever appears.

| Reason (`CliUnreadableReason`) | Sentence |
|---|---|
| `parse_error` / `invalid_content` | `I can't read your setup right now, so I won't guess.` |
| `schema_out_of_range` (**"versions don't match"**) | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` |
| `io_error` | `I can't reach your setup right now, so I won't guess. I'll keep trying.` |
| `missing_security_field` (**fails closed**) | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` |
| `exit_2` | `Something stopped me from reading your setup, so I won't guess.` |

Retry action for all: **Sync now** (see 1.6). Never say "Healthy" or "safe" in this
state.

## 1.3 Section labels (Regions 2 to 4)

| Region | Label | Optional subtitle |
|---|---|---|
| 2. Component tree | `YOUR COPILOTS` | (none) |
| 3. Join available | `AVAILABLE TO JOIN` | (none) |
| 4a. Shared integrations | `SHARED WITH YOUR TEAM` | `Ready for you. Nothing to sign into.` |
| 4b. Personal integrations | `YOUR ACCOUNTS` | (none) |

**Note on "YOUR COPILOTS":** every row in the tree is named "<name> Copilot", so
"Your copilots" is plainer and truer to Bob than "Your components". "Component" stays
the word we use when we must categorize in prose, never as a user-facing section label.
(Copy decision, flagged below.)

## 1.4 Component tree rows and layer cells (Region 2)

- **Component row:** the copilot's name, verbatim (`Claude Copilot`, `CLI Copilot`,
  `Codex Copilot`, `Knowledge Copilot`), with its worst-wins mark on the right.
- **Layer cell label** (plain words, not the raw layer id):
  - foundation -> `Core setup`
  - org -> `Your organization`
  - department -> `Your department`
  - personal -> `This Mac`
- **Layer cell detail** (right-aligned, quiet), by situation:
  - passing: (no text; the quiet dot carries it)
  - entitled, not yet joined: `Available to join`
  - needs sign-in: `Needs sign-in`
  - not entitled (honest empty slot): `You're not in this one`
  - waiting on org: `Waiting on your organization`

## 1.5 Region 3: the "Join available" row

- **Row (default):** `<Department name>` + button `Join`
  Example line as a whole: `Sales` ......... `[ Join ]`
- **Joining (in flight):** label swaps to `Joining Sales...` with a quiet spinner; the
  Join button is replaced (no ETA).
- **Joined:** the row leaves this region; the reward is the tree filling in, no toast.
- **Race / revoked (`not-entitled`, exit 0):** `Sales isn't available to you anymore.`
  (row clears on next poll)
- **Failed to join (`error`, exit 1):** `Couldn't join Sales right now. Try again.`
  with `Join` restored.
- **Disabled while offline or syncing:** `Join` disabled, tooltip / VoiceOver reason
  `Waiting for the network.` or `Finishing an update first.`

## 1.6 Region 4: integration rows

**Shared (read-only, no action, ever):**

- available: `<Integration name>` ..... `Ready`
- honest degrade (secret didn't resolve): `<Integration name>` ..... `Not available
  right now` (never green, never a button; routes to IT on its own)

**Personal (your accounts):**

- signed in: `<Integration name>` ..... `Signed in`
- signed out: `<Integration name>` ..... `Needs sign-in` + button `Sign in`
- expired / revoked: `<Integration name>` ..... `Sign in again` + button `Sign in`

## 1.7 Region 5: the action row (closed set)

Every button says exactly what it does. Never "Repair", "Force", "Fix", or "Make
healthy" (those would be the app computing). Never an "Update" button (updates install
themselves).

| Action label | Appears when | Notes |
|---|---|---|
| `Sync now` | steady state (the manual escape hatch); also the lone retry in cli-unreadable | disabled while offline, reason `Waiting for the network.` |
| `What changed` | a recent change set exists to show | opens the plain, past-tense change list |
| `Join` | a joinable department exists (Region 3) | (see 1.5) |
| `Sign in` | a personal account is signed out | opens the sign-in panel; never on a shared row |
| `Set up` | state is setup-needed | opens the first-run wizard |
| `Settings...` | always (footer) | opens Settings |

**"What changed" list:**
- Header: `Recently` (or nothing; the lines carry it)
- Line pattern (past tense, plain): `Brought your Sales department up to date.` /
  `Signed you back into Slack.` / `Updated Claude Copilot.`
- Empty: `Nothing has changed since you last looked.`

## 1.8 Region 6: the Bob lane

**Prompts (at most one, actionable, the only things ever asked of Bob):**

| Kind | Detail line | Action label |
|---|---|---|
| `sign-in` | `Slack needs you to sign in again.` | `Sign in to Slack` |
| `dirty-wip` | `You have unsaved changes in the way of an update. Nothing was touched.` | `Review your changes` |

The dirty-work prompt never offers a "discard" button (never-destroy). It has exactly
one affordance.

**Notices (informational, past tense, any number, no action, no alarm):**

| Kind | Message |
|---|---|
| `kept-you-safe` | `A setting was weakening your security, so I switched it off and told your IT team.` |
| `kept-your-working-version` | `An update didn't work out, so I kept your working version. Nothing to do.` |
| `waiting-on-it` | `Waiting on your organization to finish a bit of setup.` |

**Security banner (pinned, un-dismissable, the most persistent element):**
- Message: `A setting on this Mac was weakening your security, so I switched it off and
  told your IT team.`
- Action label (`reaffirm_label`): `Confirm my setup`
- (This banner persists until the CLI stops reporting the shadow. See the flag below:
  the exact wording of the one affordance needs an owner/UXD pass, because Bob should
  never be asked to *judge* a security event.)

## 1.9 The right-click menu (S1 minimal NSMenu)

- `About Copilot Control Tower`
- `Settings...` (Cmd-,)
- (separator)
- `Open Administration...` (only when admin-capable; absent otherwise, no disabled row)
- (separator)
- `Quit` (Cmd-q)

## 1.10 Notifications-denied fallback note

When a prompt is re-hosted in the popover because notifications are off, prepend one
quiet line above it:
- `Shown here because notifications are turned off.`
(Settings carries the plain steps to turn them back on; the app never silently
re-asks the system.)

---

# SURFACE 2: The first-run wizard (S2)

One guided window, eight steps in the built flow (welcome, detect, choose components,
departments, integrations, set up, verify, done), plus the first-class **holding**
terminal. No time estimates anywhere. Step position reads as "Step N of 8", never a clock.

Window title: `Set Up Copilot Control Tower`
Sidebar header: `Set Up Copilot Control Tower`
Sidebar section label: `SETUP`
Roadmap row titles: `Welcome` · `Detect` · `Choose copilots` · `Departments` ·
`Integrations` · `Set up` · `Verify` · `Done`

## 2.1 Welcome

- Hero title: `Welcome to Copilot Control Tower.`
- Intro: `Control Tower keeps your copilots current, quietly, in the background. Setting
  up takes a few short steps, and you won't need a terminal.`
- Primary button: `Get Started`
- Secondary button: `Quit`
- Admin opt-in (secondary control, off by default, a role declaration not a feature
  unlock): checkbox label `I'm setting this up for my organization.`

## 2.2 Detect

- Eyebrow: `STEP 2 OF 8`
- Title: `Checking what's already here`
- Intro: `Control Tower looks at what's already on this Mac before it asks you
  anything.`
- Loading line: `Checking what's already here...`
- Result card title: `What's already here`
- Result line patterns (plain, past-tense facts):
  - `Claude Copilot is current for your organization and core setup.`
  - `CLI Copilot is current for your core setup.`
  - `No personal setup on this Mac yet.`
- Buttons: `Back` / `Continue`

## 2.3 Choose copilots

- Eyebrow: `STEP 3 OF 8`
- Title: `Which copilots do you want?`
- Intro: `Pick the copilots you'd like Control Tower to set up and keep current.
  Anything your team hasn't made available to you is shown, but greyed out.`
- Section title: `Copilots`
- Disabled-row tooltip / help: `Your team hasn't made this copilot available to you.`
- Validation (all unchecked): `Pick at least one copilot to continue.`
- Buttons: `Back` / `Continue`

## 2.4 Departments

- Eyebrow: `STEP 4 OF 8`
- Title: `Departments you can join`
- Intro: `Joining a department brings in everything your team shares there. You can
  join now, or come back to this later from Settings or the menu bar.`
- Section title: `Departments you can join`
- Row captions by state:
  - available: `Available to join` + button `Join`
  - joining: `Joining...` (quiet spinner)
  - joined: `Joined`
  - not entitled: `Not available to you`
- Empty: `No departments are available to you yet. When someone adds you to one, it'll
  show up here.`
- Buttons: `Back` / `Skip for now` (tertiary) / `Continue`

## 2.5 Integrations

- Eyebrow: `STEP 5 OF 8`
- Title: `Integrations`
- Intro: `Some integrations are already set up for you because you're on the team.
  Others use your own accounts, so they need your sign-in.`
- Shared section title: `Shared with your team`
  - Shared section note: `Ready for you. Nothing to sign into.`
  - Shared row states: `Ready` / `Not available right now`
- Personal section title: `Your accounts`
  - idle: `Sign in to your accounts so Control Tower can keep them in sync.` + button
    `Sign in`
  - pending: `Waiting for you to finish in your browser...` + button `Show code`
  - signed in: `Signed in.`
  - failed (denied): `That sign-in was declined.` + button `Try again`
  - failed (expired): `That code expired.` + button `Get a new code`
  - failed (timeout): `That took too long.` + button `Get a new code`
- Buttons: `Back` / `Skip for now` (tertiary) / `Continue`

### 2.5.1 The device-flow sign-in sheet (S5)

- Title: `Sign in`
- Code label: `Your code`
- Copy button label / VoiceOver: `Copy code`
- Copied confirmation: `Copied`
- Primary button: `Open Sign-in Page`
- Waiting line (no countdown, no timer): `Waiting for you to finish in your
  browser...`
- Authorized: `Signed in.`
- Denied: `That sign-in was declined.` + `Try again`
- Expired: `That code expired.` + `Get a new code`
- Timeout: `That took too long.` + `Get a new code`
- Dismiss buttons: `Cancel` (while pending) / `Done` (once signed in)

## 2.6 Set up (materialize)

- Eyebrow: `STEP 6 OF 8`
- Title: uses the current phase label, verbatim:
  - `Setting up Claude Copilot...`
  - `Bringing in your Sales department...`
  - `Finishing up...`
- Intro: `This part runs on its own. Keep this window open, or close it and let Control
  Tower finish in the menu bar.` (No "a few minutes"; no time.)
- Progress label, if a discrete phase count is shown: `Part 2 of 4` (never a
  percentage, never a time). If no clean count, show only the phase title plus an
  indeterminate spinner.
- Footer primary (disabled, in-progress): `Setting up...`

## 2.7 Verify

- Eyebrow: `STEP 7 OF 8`
- Title: `Making sure everything's current`
- Intro: `The only success here is everything actually being up to date.`
- Loading: `Checking your setup...`
- Result (calm, not celebratory): `Everything checks out.`
- Buttons: `Continue`

## 2.8 Done

- Eyebrow: `STEP 8 OF 8`
- Title: `You're set up.`
- Intro: `Control Tower now lives quietly in your menu bar. When it has nothing to say,
  it says nothing. That quiet icon means everything's current.`
- Callout: `When you're added to a new department later, it'll show up in the menu bar
  as "Available to join," whenever you're ready.`
- Primary button: `Done`

## 2.9 Holding (the honest terminal, never a dead end)

- Eyebrow: `SETUP IS HOLDING`
- Title: `I've paused setup for now.`
- Reason line (rendered verbatim from the CLI; guaranteed plain; names the owner):
  - network: `I can't reach the network right now, so I've paused. I'll pick this back
    up as soon as you're online.`
  - organization / IT: `Your organization still has a bit of setup to finish before
    this can complete. Nothing you need to do.`
  - entitlement: `This department isn't available to you anymore, so setup can't finish
    it.`
  - unreadable: `I can't read what's already on this Mac right now, so I won't guess.`
- Secondary button: `Continue in the menu bar`
- Primary button: `Try again`

---

# SURFACE 3: Admin mode (S4)

For **Earl**, the technical operator standing up and governing the ecosystem on GitHub.
Still calm and honest, still no raw errors and no jargon dumped on anyone, but Earl is
technical enough for "team", "access", "terminal", and "pull request". No "MDM"
anywhere (it's gone).

Admin is a **baton pass**, not a wizard: the app is the confident briefer and honest
verifier; Claude Code, over a deterministic script, is the capable driver. The app
teaches, collects a plain description into a non-secret brief, hands off a copyable
command, and reads the result back from GitHub. **It fires no GitHub change of its
own.** Two sidebar sections: **Onboarding** (the once-through progression, eleven
waypoints) and **Governance** (occasional, five entries).

Window title: `Administration`

## 3.1 The handoff header (persistent, read-only)

Sits atop the window whenever an Onboarding item is selected.

- Pattern: `<Publisher status> · Setup <version> · Next: <owner>`
- Example: `Publisher done · Setup v1.4.2 · Next: you (Admin)`
- Reveal affordance (trailing): `Reveal setup ›`
- When nothing has run yet, or the handoff can't be read: `Not started yet`
- Unreadable holding line (replaces the header chips): `I couldn't read the result of
  this, so I won't guess.`

## 3.2 Sidebar labels and progression marks

Two sections. Onboarding rows carry roadmap marks that show *progress*, never
*permission*: nothing downstream is ever locked, greyed, or lock-glyphed. The map
guides; the terminal gates.

- Section `ONBOARDING`: `Orientation` · `Prerequisites` · `Contacts` ·
  `Connect GitHub` · `Describe your organization` · `Integrations` · `Secret store` ·
  `Review and hand off` · `Handed off` · `Setup check` · `Done`
- Section `GOVERNANCE`: `Add a department` · `Someone left` ·
  `Connect the shared store` · `Org setup` · `Analytics`
- Roadmap marks (shape, never color alone): done · current · upcoming.
- Connect GitHub advisory partial: while some readiness rows are short, the item shows
  a neutral partial mark and a plain count, rendered quiet gray, never red or orange,
  e.g. `Connect GitHub  3/5`. It reaches done only when all five rows are green, but
  reaching done is never a precondition for anything downstream.

Governance rows carry **no** progression marks; they are occasional entries, not a
pipeline.

## 3.3 Orientation (teach the ecosystem, then the arc)

Teaches what the ecosystem is before what to do, via progressive disclosure. Collects
nothing.

- Eyebrow: `ONBOARDING`
- Title: `Here's what you're building, and the whole path`
- Intro (what this builds): `Your copilots live in a set of shared spaces on GitHub
  that build on one another. The open-source foundation sits at the bottom. Your
  organization adds its own on top. Each department adds what only it needs. Each
  person adds their own on top of that. Everyone inherits everything beneath them, so
  you share broad capabilities widely and keep specialized ones narrow.`
- The arc (three read-only steps): `1. Describe your organization here.` /
  `2. Claude Code sets it up in your terminal.` / `3. Come back and run the Setup
  check.`
- Assurance under the arc: `This app never changes anything on GitHub itself. It gets
  you ready, hands the work to Claude Code, and checks the result.`
- Learn-more affordance: `Learn how the ecosystem works ›`
- Primary button: `Start`
- Unreadable handoff (degraded): the header reads `Not started yet`, the teach content
  still renders, and the holding line is `I couldn't read the result of this, so I
  won't guess.`

### 3.3.1 Learn more (the pushed explainer)

Two explainer views behind a segmented pager, each over a theme-aware inheritance
diagram. A leading Back returns to the calm overview.

- Eyebrow: `LEARN MORE`
- Pager segments: `How it works` · `What your team gets`
- Back button: `Back to the overview`
- **View 1, how it works:** `Each layer carries three kinds of space: one for
  instructions and agents (your harness's copilot), one for knowledge (your company's
  information), and one for integrations (tools that reach outside systems). The org
  level carries org-level agents, org-level integrations, and org information.`
- **View 2, what your team gets:** `Every person inherits your organization's agents,
  skills, knowledge, and integrations, plus their department's, on the open-source
  foundation. They build their own solutions faster, going broad with what the org
  shares and narrow with what their department adds.`
- Diagram alt text (it is content, not decoration): `The four layers, each inheriting
  everything beneath it: the open-source foundation, then your organization, then each
  department, then each person.`
- **The four example skills** (concrete, never abstractions), shown under View 2:
  - `Org: a skill that writes on-brand documents in your brand voice, and a proposal
    and SOW builder.`
  - `Accounting: a month-end reconciliation skill.`
  - `IT: an onboarding and offboarding access-runbook skill.`
  - `Sales: a call-prep brief skill.`

## 3.4 Prerequisites (before you begin)

Teaches what must be true before setup can run. Collects nothing. No failure state by
design: it names the one categorical automation boundary before anything can fail on it.

- Eyebrow: `ONBOARDING`
- Title: `Before you begin`
- Intro: `A few things need to be true before setup can run. None of them happen here.
  This is just so nothing stops you halfway.`
- Teach rows:
  - `Your organization exists on GitHub. Creating one needs billing and a person, so it
    can't be automated. If it doesn't exist yet, create it at github.com first.` +
    link `Open github ›`
  - `You are an owner of it. Only an owner can create the organization's spaces.`
  - `You have GitHub's command-line tool and Claude Code on this Mac. The next step
    checks and helps.`
- Buttons: `Back` / `Continue`

## 3.5 Contacts (who's who)

- Eyebrow: `ONBOARDING`
- Title: `Who's who`
- Intro: `Record who owns this setup, so the handoff is never guesswork. These names
  show in the handoff banner and in the setup check.`
- Field labels: `Publisher` · `Admin` · `Point of contact`
- Empty: `No contacts yet. Add the people who own this setup.`
- Save confirmation: `Saved.`
- Buttons: `Back` / `Continue`

## 3.6 Connect GitHub (readiness, refuse and teach)

Detects local readiness for the terminal session and teaches the one fix where short.
No mutation. Advisory and strongly guiding, never a hard block; the script is the real
gate.

- Eyebrow: `ONBOARDING`
- Title: `Get this Mac ready`
- Intro: `A quick check that this Mac can run the terminal session. This changes
  nothing. Claude Code checks all of this again when setup runs, and helps you fix
  anything that's off.`
- Org field label: `Organization`
- Closing note under the rows: `This step just gives you a head start. It never blocks
  the hand-off.`
- Buttons: `Back` / `Check again`

**The five readiness rows** (shape and text, never color alone). When passing, each
reads as a quiet check:

- `GitHub's command-line tool is installed`
- `You're signed in`
- `Your account is an owner of acme-co`
- `Your sign-in has the access setup needs`
- `Claude Code is installed`

**Not-ready rows, by reason** (each names one fix and its owner; the fix is copyable
where it's a command; **no bypass, ever**):

- gh not installed: `GitHub's command-line tool isn't on this Mac yet. Setup runs
  through it.` + copyable `brew install gh` + a download link
- not signed in: `You're not signed in to GitHub's command-line tool yet.` + copyable
  `gh auth login`
- not an owner: `Your GitHub account isn't an owner of this organization, so it can't
  create its spaces. Ask an owner to run this, or to make you one.`
- missing access: `Your GitHub sign-in is missing the access setup needs.` + copyable
  `gh auth refresh -s admin:org -s repo`
- Claude Code missing: `Claude Code isn't on this Mac yet. Setup runs there, so you'll
  want it before you hand off.`

**Whole-check states:**

- idle: rows read `Not checked yet.`
- working: header status `Checking your GitHub access...` (no ETA)
- ready (all five green): `Your GitHub access can set up acme-co.` and Continue is free
- degraded (the check itself couldn't run): `Something stopped me from checking your
  access, so I won't guess.`
- Copy affordance on any command: `Copy` / confirmed `Copied`

## 3.7 Describe your organization (teach, harness, live plan)

Teaches why departments get their own spaces, asks the harness once org-wide, collects
identity and departments, and shows the concrete plan by real name. Nothing is created
here.

- Eyebrow: `ONBOARDING`
- Title: `Describe your organization`
- Intro: `Tell setup your organization's name, the harness it builds with, and its
  departments. As you type, you'll see exactly what will be created. Nothing is created
  here. This is the plan setup will follow.`
- **Teach block (why departments get their own spaces):** `Departments get their own
  spaces so specialized capabilities are tailored to how that department works.
  Accounting's spaces hold Accounting's skills and knowledge, and each department's
  people inherit the whole organization's on top.`
- **Add-later promise (prominent, not a footnote):** `You don't have to add every
  department now. Adding one later is safe. Setting up again only adds what's new and
  never touches what's already there.`
- **Harness question:** `Which development harness does your company build with?` with a
  two-segment control `Claude Code` | `Codex` (the org-wide default; acme-co is a Codex
  shop).
- **Harness reassurance (right under the control):** `This is your organization's
  default. Anyone can still use the other harness for themselves, on the open-source
  foundation plus their own personal setup. And you can add the second harness for the
  whole organization later, as a safe re-run that only adds what's new.`
- Field labels: `Organization name` · `Departments` (each row removable) · add-row
  `Add a department`
- **Invalid-slug refusal (inline, on the offending field):** `Give this department a
  name using letters, numbers, and dashes.`

**The "What this will create" plan card** (fills live as Earl types; mono repo and team
names, one per line, grouped by scope; never an abstract summary):

- Card header: `Nothing is created here. This is the plan setup will follow.`
- Empty prompt (before a valid org name): `Type your organization's name to see the
  plan.`
- Org block, opened by `Three shared spaces for your whole organization:` then
  `acme-co/codex-copilot`, `acme-co/knowledge-copilot`, `acme-co/cli-copilot`, tagged
  `Private.`
- Per-department block (Accounting shown), opened by `Three spaces for the Accounting
  department:` then `acme-co/codex-copilot-accounting`,
  `acme-co/knowledge-copilot-accounting`, `acme-co/cli-copilot-accounting`, tagged
  `Private.`, closed by `An Accounting team that can reach them.` (Sales repeats the
  shape with `-sales`.)
- Org-wide line: `Your whole organization set to read by default.`
- Add-later promise repeated at the card's foot: `You don't have to add every
  department now. Adding one later is safe. Setting up again only adds what's new.`
- Enumeration grammar: switching the harness re-derives every `<harness>-copilot*` name
  in one coordinated update; the reassurance copy stays put.
- Buttons: `Back` / `Continue` (available once a valid org name exists)

## 3.8 Integrations (education only)

Education only. Teaches the integration model and previews how integrations will
arrive. **Collects nothing.** No declaration form and no secret-shape refusal on this
surface.

- Eyebrow: `ONBOARDING`
- Title: `Integrations`
- Intro: `An integration here is a small command-line tool a developer builds, so a
  copilot can reach a system like Salesforce or your calendar. It isn't something you
  switch on.`
- **Education (two beats):**
  - `It cascades.` `Built and published for the whole organization, it's inherited by
    every department. Published for one department, it belongs only there. Published
    nowhere, it exists for no one.`
  - `The key lives elsewhere.` `An integration names the key it needs. The key never
    comes near this app. It lives in the shared store, handed out only to the right
    team.`
- **How integrations will arrive (a four-beat lifecycle, read-only):**
  1. `An engineer on a department builds skills, agents, and integrations inside that
     department's spaces. Give an engineer write access to a department's team and they
     can build there.`
  2. `Each integration is added to a registry, a plain document that lives in the same
     space and lists what has been built.`
  3. `Merging that document to the main copy publishes the integration.`
  4. `From then on, the people entitled to that space see it, and the app your team uses
     can let them know when a new one arrives.`
- **The registry preview (a labeled, inert frame with example data only):**
  - Frame label: `PREVIEW · not live`
  - Example rows: `acme-co/cli-copilot-sales · registry (example)`, then
    `salesforce-lookup   needs SALESFORCE_API_KEY` and `calendar-read   needs
    GOOGLE_CAL_TOKEN`
  - Caption: `This is what a published registry will look like. It is an example, not
    your data, and nothing here is clickable.`
- **Honest ending:** `There's nothing to set up here today. No integrations exist yet,
  and that's expected. They arrive when your departments' engineers build and publish
  them.`
- Buttons: `Back` / `Continue`

## 3.9 Secret store (educate, then connect or defer)

Educates on what a store is and its runtime use, then connects or defers honestly. The
secret-shape refusal is **retained here**. No hard gate on finishing standup.

- Eyebrow: `ONBOARDING`
- Title: `Your shared secret store`
- Intro (educate): `A shared secret store is one service that holds your organization's
  keys and hands them out by team. Shared integrations need it: an integration names the
  key it needs, and at runtime the store checks that the person is on the right GitHub
  team and only then hands over the key. That is why a key never lives in a repo or in
  this app.`
- **Connect a store (form):**
  - Section label: `Connect a store`
  - Field labels: `Store type` · `Store address` · `Which teams can use it`
  - Store-address help: `This is a web address, not a secret.`
- **No store yet? (connect-or-defer, both honest):**
  - Section label: `No store yet?`
  - Truth line: `Shared integrations can't work until you connect a store. You have no
    integrations yet, so you can finish setting up now and connect a store before your
    first one is built.`
  - Pause and go get one: `Pause and go get one. Common shared stores are 1Password,
    Infisical, and Vault (also called OpenBao). Set one up, then come back with its web
    address.` + link `How to set one up ›`
  - Defer and finish (honest, with its consequence): `Skip this for now. You'll be
    reminded to connect a store before your first shared integration can work.` + button
    `Skip for now`
- **Refusals:**
  - Address invalid (on blur): `That doesn't look like a valid address.`
  - Secret-shape refusal (a hard block; value blocked, never saved, never logged): `That
    looks like a secret. This setting never holds secrets. Secrets live in the store
    itself, or in your keychain, never here.`
- **Connected:** `Connected. This will be included when you hand off.`
- Buttons: `Back` / `Continue` (Continue is never gated; deferral is a valid path to
  Done)

## 3.10 Review and hand off (the baton pass)

Enumerates concretely what will be created, writes the non-secret brief, and generates
the copyable command. **No "set up my org" mutation.**

- Eyebrow: `ONBOARDING`
- Title: `Review and hand off`
- Intro: `Here's everything setup will create. Copy the command below, open your
  terminal, and paste it. Claude Code walks you through the rest and checks everything
  with GitHub as it goes.`
- **Never-destroy promise (pinned above the enumeration):** `This adds and updates. It
  never deletes or overwrites anything already there.`
- **What setup will create** (the same real names from Describe):
  - `Org spaces: acme-co/codex-copilot, acme-co/knowledge-copilot, acme-co/cli-copilot.
    Private.`
  - `Accounting: three spaces and an Accounting team.`
  - `Sales: three spaces and a Sales team.`
  - `Your organization's setup file (ecosystem.yml).`
  - `Your whole organization set to read by default.`
  - `Harness: Codex.` and the store state: `Store: connected.` or `Store: not connected
    yet.`
- **The brief-file card:**
  - `Setup wrote a plain description of your organization you can read:` + mono path
    `~/…/CopilotControlTower/standup-brief.md` + affordance `Reveal ›`
  - At a glance: `acme-co · Codex · 2 departments · store connected.`
  - Honesty line: `It carries no secrets and no integrations.`
- **The command block:**
  - One mono line (placeholder shape, a TA contract item): `claude --skill
    admin-bootstrap <points at the file above>`
  - Copy affordance (attached to the command): `Copy the setup command` / confirmed
    `Copied`
  - What crosses the boundary: `This hands Claude Code a plain description of your
    organization. It carries no secrets. Claude Code checks it with you, then does the
    work.`
  - Return instruction: `When Claude Code says it's done, come back here and run the
    Setup check.`
  - Quiet copy-only path: `When you've pasted it, come here to wait ›`
- **Brief-write failure (retry; the command is withheld):** `I couldn't write the setup
  file, so I won't hand off a command that points at nothing. Try again.`
- Footer: `Back` / `Open Terminal` (advances to Handed off). The primary is never "Set
  up my org."

## 3.11 Handed off (the blind resting state)

An honest blind resting state while the terminal works, and the one way back. **No fake
spinner, ever;** stillness is the honesty.

- Eyebrow: `ONBOARDING`
- Title: `Setup is running in your terminal`
- Intro: `Claude Code is setting up your organization now.`
- Resting body: `This app can't see your terminal, so it won't guess how it's going.
  When Claude Code says it's done, run the Setup check and this app will read the result
  straight from GitHub.`
- The one action: `Run the Setup check`
- Close-safe reassurance (always visible): `You can close this. Your organization's
  setup lives on GitHub, and the Setup check reads it fresh every time.`

## 3.12 Setup check (post-run verification, from GitHub truth)

Post-run verification read from GitHub truth: red and green, owner-named, count never
score, drift shown honestly. **Computes no verdict.**

- Eyebrow: `ONBOARDING`
- Title: `The setup check`
- Intro: `An honest look at what's really on GitHub now. Every red names who has to fix
  it.`
- **Drift note (persistent, under the title):** `This reads what's really on GitHub, not
  what you typed here. If setup did more or less than your plan, you'll see it below.`
- Row status words (shape and text, never color alone):
  - pass: `Ready`
  - fail: the plain `detail` line for that check
  - unknown (**never green**): `Couldn't check this`
- Owner tag per red or unknown row: `Admin` / `GitHub org owner` / `IT infra` / `The
  foundation (external)`
- **Beyond-plan present row** (present, not error; no owner, no fix, not counted): a
  neutral present mark + the item name + caption `This wasn't in your plan. Setup added
  it, and that's fine.`
- **Deferred-store row** (a fourth honest state, neutral, never red and never orange,
  not counted): owner `Admin`, line `Not connected yet. Shared integrations can't work
  until you connect one. You chose to do this later.` + action `Connect ›` (jumps to
  Connect the shared store)
- Summary (a plain count, no score, no percentage, no gauge): `1 thing must be fixed.
  Nothing couldn't be checked.` When clean: `Everything's ready to hand over.`
- Working: `Checking what's really on GitHub...` (no ETA)
- Admin-owned red drill-in: the plain `detail` + `Go fix this` (jumps to the surface
  that authored the offending input)
- Empty (never run): `Run the setup check before you hand this over. It catches blockers
  before your organization does.` + CTA `Run the setup check`
- Footer: `Run it again` / `Continue` (to Done, when clean)

## 3.13 Done, and what now

Calm confirmation, then the two forward actions. **No celebration.**

- Eyebrow: `ONBOARDING`
- Title: `Your organization is set up`
- Intro: `The spaces exist, the teams can reach them, and your setup file is in place.
  Two things to do next.`
- **Invite the team, on GitHub:** `People join a department by being added to its team
  on GitHub. Add someone to the Sales team and they can join Sales from their own
  copilot. This app never manages people. GitHub does.` + link `Open your teams ›`
- **Point users at the app:** `Your team installs Copilot Control Tower themselves, and
  it sets them up from what you just built. Send them the app, and they'll see the
  departments they're on.`

---

**GOVERNANCE surfaces** (occasional; no progression marks). The same describe / hand off
/ verify instrument as standup, plus guidance for the acts that belong on GitHub and in
the store.

## 3.14 Governance: Add a department (or the second harness)

Entry to steady-state; frames the safe re-run, then routes into Describe (3.7).

- Eyebrow: `GOVERNANCE`
- Title: `Add a department`
- Intro: `Add a department here. Setting up again only adds what's new and never touches
  what's already there.`
- Existing-state frame: `Your organization already has: Accounting, Sales, on Codex. Add
  a new department and you'll see the plan for just its three spaces and its team. You
  can also add Claude Code alongside Codex for the whole organization; it only adds the
  new claude-copilot spaces and leaves everything else alone.`
- Primary: `Describe the addition` (opens Describe with existing units pre-filled and
  locked, only the addition editable; then reuses Review, Handed off, and the Setup
  check)

## 3.15 Governance: Someone left (guidance, not management)

Instructional guidance for a leaver. Renders the person's teams and the named keys to
rotate. **Triggers nothing.** No offboard button.

- Eyebrow: `GOVERNANCE`
- Title: `Someone left`
- Intro: `This app doesn't manage people. When someone leaves, remove them from their
  teams on GitHub. Then rotate the keys those teams could reach in your shared store, so
  their old access is worthless.`
- Lookup field label: `Who left` (with a look-up action)
- **Teams they were on (remove them on GitHub):** each row is a team name + `Open on
  GitHub ›` (for example `Accounting team`, `Sales team`)
- **Keys to rotate (in your shared store):** each row is a key name, its department, and
  `Open the store ›` (for example `SALESFORCE_API_KEY (Sales)`, `NETSUITE_TOKEN
  (Accounting)`)
- Unreadable: `I couldn't read the result of this, so I won't guess.`

## 3.16 Governance: Connect the shared store (the deferred case)

The governance home for connecting a store, for the org that deferred at standup or is
adding one before its first integration ships. Reuses the educate-and-connect form; a
collect surface whose write is authored by the script through a hand-off.

- Eyebrow: `GOVERNANCE`
- Title: `Connect the shared store`
- Intro: `Connect the store that holds your organization's shared keys. Your
  integrations will need it before they can work. A shared secret store hands out keys
  by GitHub team, so a key never lives in a repo or in this app.`
- Field labels: `Store type` · `Store address` (help `This is a web address, not a
  secret.`) · `Which teams can use it`
- Secret-shape refusal (retained): `That looks like a secret. This setting never holds
  secrets. Secrets live in the store itself, or in your keychain, never here.`
- **How this is added (never-destroy, inline):** `This adds your store pointer to your
  organization's setup. It never deletes or overwrites anything already there. Claude
  Code makes the change in your terminal, the same way it set up your organization.`
- Primary: `Copy the command to add it` / confirmed `Copied` (then routes through Handed
  off and the Setup check, where the store row flips to `Ready`)

## 3.17 Governance: Org setup (read-only summary)

Everything the org distributes, in one read-only place. Merges the old store-config
panel. Collects nothing.

- Eyebrow: `GOVERNANCE`
- Title: `Your organization's setup`
- Intro: `Everything your organization hands out, in one place. This comes from your
  organization's setup on GitHub. It isn't editable here, by design.`
- Section `COPILOTS & HARNESS`: `Harness: Codex.` plus the copilots and their versions
  (`Codex · Knowledge · CLI`)
- Section `DEPARTMENTS`: `Accounting · Sales`
- Section `PUBLISHED INTEGRATIONS` (rolled up from the departments' registries), empty:
  `None published yet.`
- Section `WHERE YOUR SHARED KEYS COME FROM`:
  - connected: the store address, read-only, under `Where your shared keys come from`
  - not connected (deferred): `Not connected yet. Connect one before your first shared
    integration can work.` + jump `Connect the store ›` (opens 3.16)

## 3.18 Governance: Analytics (off by default)

- Eyebrow: `GOVERNANCE`
- Title: `Usage data`
- Off-by-default note (intro): `Off. Nothing is shared unless you turn this on and your
  organization signs off on it.`
- Switch label: `Share anonymous usage data`
- Read-only "what would be sent" heading: `What this would share`

---

# SURFACE 4: Steady-state surfaces (completeness)

Not in the three requested blocks, but part of the full experience. Included so the
voice stays consistent end to end.

## 4.1 Update and rollback (S9), rendered inline, never a dialog

- checking / downloading / verifying / staging: `Updating Control Tower...`
- ready / available: `An update is ready. I'll install it on my own.` (or silence)
- rolled-back (the hero, past tense, understated, no action): `An update didn't work
  out, so I kept your working version.`
- error (plain, calm, because the working version was kept): render
  `UpdateState.message` verbatim; never a raw signature or watchdog string.
- idle / up-to-date: render nothing.

## 4.2 Access turned off, the user side of "Someone left" (a quiet Bob-lane notice)

- `Your access here was turned off. Your unsaved work was kept: <list>.`
- when empty: `Your access here was turned off. Nothing of yours was in the way.`

## 4.3 Settings (S3) tab labels

- `General` · `Copilots & layers` · `Integrations` · `Your keys across your Macs` ·
  `Advanced` · `Administration` (conditional)

## 4.4 Personal Key Sync (S13), Settings tab `Your keys across your Macs`

- Switch label: `Sync my keys across my own Macs`
- Scope line (load-bearing reassurance): `Your keys, your Macs only. Never shared,
  never in a shared place.`
- Roster heading: `Your Macs`
- Roster row states: `Enrolled` (this Mac) / `Enrolled` + button `Remove` (other) /
  `Not syncing` + button `Enroll` (known, off)
- `What syncs`: `The accounts you signed into yourself.`
- `What never syncs`: `Anything shared with your team, and anything your organization
  set up for you.`
- Conflict (two Macs differ), by machine and recency, never the secret value:
  `Two of your Macs have a different value for <account>. Which do you want to keep?`
  Option labels: `Keep the one from <Mac name> (set <when>)`
- Empty (off / no other Macs): `Turn this on to stop copying keys between your Macs.`
- Error: `Couldn't change key sync right now. Try again.`
- Remove-another-Mac confirm: `Stop <Mac name> from syncing your keys? You can turn it
  back on later.`

## 4.5 The author conflict chooser (S7, author tier only, never Bob)

- Title: `Two edits collided`
- Intro: `You and a teammate both changed this. Pick what happens. Nothing is lost
  either way.`
- Options (plain, one sentence each; "Keep both" is the pre-selected safe floor):
  - `Keep both` -> caption `Keep your version and theirs, side by side.`
  - `Keep yours` -> caption `Use your version.`
  - `Keep theirs` -> caption `Use your teammate's version.`
  - `Park and ask an author` -> caption `Set it aside for someone to look at.`
- Primary: `Continue`
- On escalate: `Parked for an author to look at.`
- On finish: `Done.`
- Error (degrades to the safe exit, never a raw git error): `Couldn't finish that, so I
  parked it safely for an author.`

---

# Appendix A: Voice quick-reference (the We Say / We Don't Say table for this app)

| We say | We don't say |
|---|---|
| `Codex Copilot needs you to sign in.` | `Something needs your attention.` |
| `Waiting for the network.` | `Healthy` (when it can't prove it) |
| `An update is waiting on your organization.` | `Review and approve this update.` |
| `Kept your working version.` | `Update failed. Contact support.` |
| `Everything is set up.` | `All good! You're all set!` (with a green checkmark) |
| `I won't guess.` | a fabricated status, a computed score |
| `Your unsaved work was kept.` | `Some files were removed.` |
| `Available to join` | `New department unlocked!` |
| `Your team hasn't made this available to you.` | `You are not entitled to this component.` |

# Appendix B: Words banned from every user surface

`MDM`, `entitled` / `entitlement` (as a bare word to Bob), `repo` / `repository` (on a
Bob surface; "your team's shared space" or "address" instead), `product` (meaning a
copilot), `component` (as a section label; fine in prose), `YAML`, `daemon`, `parse`,
`schema`, `token`, raw `git` / `serde` / signature / watchdog strings, `Aviator` (the
dead codename). And no em-dashes, anywhere.

# Appendix C: Copy decisions worth the owner's eye

1. **"Your copilots" vs "Your components" as the tree label.** This deck uses **Your
   copilots** on user surfaces (every row is a named Copilot; it is plainer for Bob) and
   reserves **component** for prose and internal categorization. The interaction spec's
   voice anchor says the app "says component"; this is a deliberate softening for the
   one place it is a headline. Confirm.
2. **The security-banner affordance wording.** The banner is un-dismissable and carries
   one action (`reaffirm_label`). "Re-affirm your version" is engineer-speak, and SOUL
   is emphatic that Bob is **never** asked to *judge* a security event. This deck
   proposes `Confirm my setup`, but the honest answer may be that this affordance should
   not be a Bob decision at all. Flagged to route to UXD.
3. **"Settings..." vs "Preferences...".** This deck standardizes on **Settings...**
   (current macOS convention, Ventura and later). The built code still says
   "Preferences...". A trivial swap, called out so it is intentional.
4. **Layer names in plain words.** Bob never sees `foundation / org / department /
   personal`; he sees `Core setup / Your organization / Your department / This Mac`.
   Confirm these map cleanly for every org shape (some orgs may not use "department").
5. **The materialize phase count.** Named phases carry progress; a `Part N of M` count
   is offered only when the CLI emits discrete completed-phase counts. If it doesn't,
   show the phase title alone. No percentage, ever.

---

*Copy deck complete. Every placeholder string in `control-tower-interaction-spec.md` §8
now has a final value here. Route to uids (Stage 3 visual system) for how these strings
sit in the six popover regions and the two integration registers, and back to the
implementer to replace the current `native/*.swift` copy (notably the "CSE components,
not products" and "because you're entitled" strings, which leak vocabulary Bob would not
use).*
