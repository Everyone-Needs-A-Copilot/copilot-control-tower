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

For **Earl**, the IT operator standing up and governing the ecosystem. Still calm and
honest, still no raw errors and no jargon dumped on anyone, but Earl is technical enough
for words like "team", "access", and "pull request". No "MDM" anywhere (it's gone). Two
sidebar sections: **Onboarding** (do once) and **Governance** (occasional).

Window title: `Administration`

## 3.1 The handoff header (persistent, read-only)

- Pattern: `<Publisher status> · Setup <version> · Next: <owner>`
- Example: `Publisher done · Setup v1.4.2 · Next: you (Admin)`
- When nothing has run yet: `Not started yet`

## 3.2 Sidebar labels

- Section `ONBOARDING`: `Prerequisites` · `Contacts` · `Repositories & teams` ·
  `Authors & keys` · `Secret store` · `Seed` · `Policy signers` · `Preflight`
- Section `GOVERNANCE`: `Deprovision` · `Analytics` · `Secret store config`

## 3.3 Prerequisites

- Title: `Before you begin`
- Intro: `A short checklist of what you'll need on hand to stand up the ecosystem. None
  of it is done here, this is just so nothing stops you halfway.`
- Empty / not-started: `Nothing checked yet. Work down the list when you're ready.`

## 3.4 Contacts

- Title: `Who's who`
- Intro: `Record who owns this setup, so the handoff is never guesswork. These names
  show in the handoff banner and in the setup check.`
- Field labels: `Publisher` · `Admin` · `Point of contact`
- Empty: `No contacts yet. Add the people who own this setup.`
- Save confirmation: `Saved.`

## 3.5 Repositories & teams (the entitlement spine)

- Title: `Departments and access`
- Intro: `Access is how someone joins a department. Give a team read access and its
  people can join the department. Give write access and they can author it.`
- Grant, in plain language (not raw permissions):
  - read grant: `People on this team can join the Sales department.`
  - write grant: `These people can author the Sales department.`
- Add control: `Add a team`
- Empty (no grants on a department): `No one can join this department yet. Give a team
  read access to let them in.`
- Loading: `Applying access...`
- Error: `Couldn't change access right now. Try again.`
- Success: `Access updated.`

## 3.6 Secret store setup

- Title: `Connect your shared secret store`
- Intro: `Your organization's shared integrations (Salesforce, Workday, Microsoft) get
  their keys from one shared store. Connect it once here. You never paste a key into
  this app.`
- Field labels: `Store type` · `Store address` · `Which teams can use it`
- Store-address help: `This is a web address, not a secret.`
- **The secret-shape refusal (a hard block, not a warning):**
  `That looks like a secret. This setting never holds secrets. Secrets live in the
  store itself, or in your keychain, never here.`
  (The rejected value is not saved and not logged.)
- Address validation error: `That doesn't look like a valid address.`
- Success: `Connected. This will be included when you open your setup pull request.`

## 3.7 Seed generator

- Title: `Build your setup`
- Intro: `Fill in the sections below and Control Tower writes the setup file for you,
  then opens a pull request. You never touch a config file or a terminal.`
- Section titles: `Copilots` · `Departments` · `Versions` · `Integration references` ·
  `Policy signers` · `Usage data`
- Add-row labels: `Add a department` · `Add a signer`
- Preview heading: `What this will create`
- Validate button: `Check it over`
- Validation summary (a count, never a score): `2 things to fix` /
  `Everything checks out.`
- Per-field error pattern (plain, attached to the field): `<plain message>` (for
  example `Give this department a name.`)
- Open-PR button (enabled only once valid): `Open pull request`
- Opening: `Opening pull request...`
- Success: `Opened pull request #123.` + link `Open in browser`
- Empty (first-time author): `Write your ecosystem setup without touching a config
  file. Control Tower turns your answers into a valid setup file and opens the pull
  request for you.` + CTA `Start from your organization`

## 3.8 Preflight (the setup check)

- Title: `Run the setup check`
- Intro: `An honest red and green list before you hand this over. Every red names who
  has to fix it, so you always know who to chase.`
- Run button: `Run the setup check`
- Re-run button: `Run it again`
- Row status words (shape and text, never color alone):
  - pass: `Ready`
  - fail: the plain `detail` line for that check
  - unknown (**never green**): `Couldn't check this`
- Owner tag per red or unknown row: `Publisher` / `Admin` / `You` / `The user`
- Summary (a plain count, no score, no percentage, no gauge):
  `2 things must be fixed. 1 couldn't be checked.`
  When clean: `Everything's ready to hand over.`
- Drill-in on a red row: expands to the plain `detail` plus a fix affordance:
  - Admin-owned: `Go fix this` (jumps to the right onboarding step)
  - Publisher-owned: the plain instruction + the handoff reference
  - User-owned: the plain description, no dead end
- Empty (never run): `Run the setup check before you hand this over. It catches
  blockers before your organization does.` + CTA `Run the setup check`

## 3.9 Governance: Deprovision (IT side)

- Title: `Someone left`
- Intro: `When a person's access is revoked, this is what happened on their Mac.
  Control Tower renders it, it never triggers it.`
- Outcome line patterns:
  - `Their access was revoked and their shared keys were rotated.`
  - Retained work (prominent, the never-destroy reassurance): `Their unsaved work was
    kept: <list>.` / when empty: `No unsaved personal work was in the way.`
  - Removed count (neutral, no editorializing): `<N> item(s) removed.`
- The one case allowed to read as an alarm (honesty outranks calm), when secrets were
  involved: `Heads up: secrets were involved in this. Your IT team has been told.`
- Unreadable: `I couldn't read the result of this, so I won't guess.`

## 3.10 Governance: Analytics

- Title: `Usage data`
- Switch label: `Share anonymous usage data`
- Off-by-default note: `Off. Nothing is shared unless you turn this on and your
  organization signs off on it.`
- Read-only "what would be sent" heading: `What this would share`

## 3.11 Governance: Secret store config

- Title: `Shared secret store`
- Read-only endpoint heading: `Where your shared keys come from`
- Note: `This comes from your organization's signed setup. It isn't editable here, by
  design.`

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

## 4.2 Deprovision (user side), a quiet Bob-lane notice

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
