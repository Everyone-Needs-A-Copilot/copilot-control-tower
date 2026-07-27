# Copilot Control Tower: Copy Deck

Final UX copy for the native macOS app, organized by surface and state so an
implementer can drop each string straight into `native/*.swift`. This deck is the
`cw` (copywriting) deliverable the interaction spec closes on
(`control-tower-interaction-spec.md` §8: "route to cw for final microcopy of every
placeholder string herein").

**Ground truth read first:** `SOUL.md` (§7 Voice & Tone), the interaction spec, and
`docs/10-reference/cse-alignment-decisions.md` (the vocabulary).

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
| `not_installed` (**new**) | `The setup helper isn't installed on this Mac yet.` |
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
| `permission-needed` | `GitHub needs one more permission before this Mac can finish setting up.` | `Grant this on GitHub` |

The dirty-work prompt never offers a "discard" button (never-destroy). It has exactly
one affordance.

**Notices (informational, past tense, any number, no action, no alarm):**

| Kind | Message |
|---|---|
| `kept-you-safe` | `A setting was weakening your security, so I switched it off and told your IT team.` |
| `kept-your-working-version` | `An update didn't work out, so I kept your working version. Nothing to do.` |
| `waiting-on-it` | `Waiting on your organization to finish a bit of setup.` |

**One notice carries an action** (an offer is not a fault, so it is a notice and not a prompt, the same call the projects offer made):

| Kind | Message | Action label |
|---|---|---|
| `connection-offer` | `This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.` | `Add the connection` |

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

One guided window, **ten** steps in the built flow, plus **three** first-class inline screens that add no sidebar row and change no step number: the **holding** screen (§2.9), the **organization question** (§2.1.1), and the **one question first** screen (§2.2.1). No time estimates anywhere. Step position reads as `Step N of 10`, sentence case, never a clock.

**Two steps have no section of their own below.** `Connect GitHub` (step 2) is the device-flow sign-in, whose strings live in §2.5.1 and whose one inline question lives in §2.1.1. `Your projects` (step 7) is specified in full in `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-project-setup-spec.md`. The eyebrows in §2.2 through §2.8 below carry their correct built positions.

Window title: `Set Up Copilot Control Tower`
Sidebar header: `Set Up Copilot Control Tower`
Sidebar section label: `SETUP`
Roadmap row titles: `Welcome` · `Connect GitHub` · `Detect` · `What you're getting` · `Departments` · `Integrations` · `Your projects` · `Set up` · `Verify` · `Done`

## 2.1 Welcome

- Hero title: `Welcome to Copilot Control Tower.`
- Intro: `Control Tower keeps your copilots current, quietly, in the background. Setting
  up takes a few short steps, and you won't need a terminal.`
- Primary button: `Get Started`
- Secondary button: `Quit`
- Admin opt-in (secondary control, off by default, a role declaration not a feature
  unlock): checkbox label `I'm setting this up for my organization.`

### 2.1.1 Which organization are you with? (inline over Connect GitHub)

Rendered the way Holding and §2.2.1 are rendered: a `StepShell` over the Connect GitHub stage, no sidebar row, no step-number change, `accent` blue and never orange, because this is a question and not a pause. Entered when `cc auth login --json` returns `org-required`, which on a genuinely fresh Mac is every time. Sign-in needs the organization's GitHub App sign-in ID, that ID now comes from a small public file the organization publishes, and fetching it means knowing which organization. Nothing on a fresh Mac does. The CLI cannot ask, because it must stay non-interactive and machine-readable, so asking is the app's job.

**Never a Holding variant.** `holdingInfo(for:origin:)` returns `nil` for `org-required`, exactly as it already does for `signed-out`, and `routeCliError` enters this screen. Before this section, `org-required` fell through to H2's `Something stopped me from reading your setup, so I won't guess.` on every fresh Mac, which is the failure class §2.10 exists to remove.

**The app exhausts everything it can know before it asks.** First, an organization pointer already set on this Mac, in which case `org-required` never fires and no screen appears. Then the admin standup brief's `org` field, tried **silently** with nothing rendered (the admin rule below). Only then does it ask.

- Eyebrow: `BEFORE YOU SIGN IN`
- Title: `Which organization are you with?`
- Intro, by how we got here (the first sentence is constant; only the second changes):
  - Nothing known, empty field: `Your organization sets up its own sign-in, so I need to know which one to ask. You'll find its name on the page you downloaded Control Tower from, and in the email that sent you there.`
  - This Mac's own standup name was tried and didn't work, field prefilled with it: `Your organization sets up its own sign-in, so I need to know which one to ask. This Mac already set up Acme-Co, so I tried that first.`
- Field label: `Your organization's name on GitHub`
- Placeholder: `Acme-Co`
- Helper text, always present: `The short name in your organization's GitHub address, like the Acme-Co in github.com/Acme-Co.`
- Leading actions: `Help me find it`, then `Continue in the menu bar`
- Primary action: `Continue to sign in`
- Primary disabled hint, empty field: `Add your organization's name, or select Help me find it.`

**The field takes an address as happily as a name.** `https://github.com/Acme-Co`, `github.com/Acme-Co/copilot-bootstrap`, and `github.com/orgs/Acme-Co/repositories` all rewrite in place to `Acme-Co`, with no message: the visible rewrite is the feedback. Text it cannot reduce is left exactly as typed and answered by validation, never silently discarded.

**Validation**, shown only after the field is left or the primary is pressed, never while the first characters are typed (Admin's own `orgSlugTouched` discipline):

| Condition | Message | Extra affordance |
|---|---|---|
| Contains spaces | `Your organization's name on GitHub is one word, with dashes instead of spaces. Acme Corporation is usually Acme-Corporation.` | Button `Use Acme-Corporation` |
| Contains `@` | `That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.` | none |
| Anything else GitHub would not accept | `Names on GitHub use letters, numbers, and single dashes, and nothing else.` | none |

The spaces message and its button both echo the person's own typed value back, with runs of spaces turned into single dashes, so the transform is shown on the thing they actually typed.

**What comes back:**

| CLI result | Where it goes |
|---|---|
| Device code returned | Connect GitHub's ordinary code card (§2.5.1). No confirmation and no toast: silence is the success state. |
| `org-not-found` | Stays here. Under the field: `I couldn't find Acme-Coo on GitHub. It may be spelled differently there, and whoever looks after your Mac will know.` The field keeps what was typed, so the difference stays visible. |
| `no-company-app` | H6, or H7 self-serve on an admin Mac, both unchanged, plus the `Use a different organization` action §2.9 now carries. The organization is real and has not published yet. That is never the person's mistake and must never read as one. |
| `network-unavailable` | H5, offline, existing intro verbatim. |
| The pointer could not be written to this Mac | H2 with `environment-error`'s existing intro, verbatim. |

**The pointer is written only after the sign-in ceremony actually starts** (`cc config set github_app.org <name>`, machine config, once the device code comes back). A name that never resolved is never persisted, so a wrong answer costs one keystroke and leaves nothing behind.

**The admin's own Mac: try the standup name silently.** The standup brief already carries `org` beside the `github_app.client_id` H7 self-serve reads. On `org-required`, if that name resolves and hasn't already been tried this session, the app retries with it and renders nothing; a success means the person never sees this screen. A confirmation screen here would consist entirely of "this Mac already set up Acme-Co, press Continue," and a screen whose whole content is *everything is fine* is the one thing this deck refuses to render anywhere else. Three things make silence safe: nothing is persisted until sign-in actually starts, so a stale name leaves nothing behind; every failure is visible and explained, landing on this screen's second intro variant or on a hold that carries a way back; and the value came from a file this Mac's own admin app wrote from something the admin typed by hand. H7 self-serve reads the same brief and still shows a screen, but for a reason that doesn't apply here: there the fix is a command the app genuinely cannot run. The standup should also write the pointer itself (Appendix E.3), after which this branch is only a recovery path for Macs set up before that change.

**Handing the name over instead of asking for it: what was deferred.** A `copilotcontroltower://connect?organization=` link from the org's download page would remove the paste entirely, and it was designed and then deferred rather than rejected. It registers a URL handler in both builds that anything on the machine can invoke, on the one code path that runs before any credential exists, and to stay safe it would have to render a confirmation screen anyway, so it buys a saved paste at the cost of new externally-triggerable surface. The copyable name on the page (Appendix E.2) carries nearly all of the benefit with none of that. Revisit once the flow has real usage.

### 2.1.2 Finding your organization's name (the sheet behind `Help me find it`)

§2.9.2's pattern, inverted. There, the block holds a command for a technical person to run. Here the person is not missing a command, they are missing a fact, and the fact belongs to their admin. So the copyable block is the message that asks for it, already written. Actor-competence (invariant #5): when the fix is not theirs, hand them the shortest route to whoever owns it.

- Title: `Finding your organization's name`
- Intro: `It's on the page you downloaded Control Tower from, and in the email that sent you there. If you can't find either, send this to whoever looks after your Mac.`
- Block label: `The message`
- Block contents, verbatim: `Hi, I'm setting up Copilot Control Tower on my Mac. It's asking for our organization's name on GitHub, the short name in our GitHub address. Can you send it to me?`
- Copy affordance: `Copy this message` / confirmed `Copied`
- Primary: `Done` (closes the sheet, returns focus to the field)
- The sheet never links to GitHub: opening the organization's page requires the very thing they don't have.

## 2.2 Detect

- Eyebrow: `Step 3 of 10`
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

### 2.2.1 One question first (inline over Detect)

Rendered the way Holding is rendered: a `StepShell` over the Detect stage, no sidebar row, no step-number change, `accent` blue and never orange, because this is an offer and not a pause. Entered when the CLI's plan carries at least one ask row. Never a Holding variant: an adoptable plan comes back `changes-required` or `applied`, never `blocked`, so it is structurally unreachable from Holding.

An **ask row** is any inventory item with `reversible == true`, in the CLI's order, checkbox pre-selected. A **review row** is any item with `action == "review"`, no checkbox, trailing `Kept as is`. Rows are grouped into two cards by `scope`; neither the scope word nor the item id ever appears on screen.

- Eyebrow: `ONE QUESTION FIRST`
- Title: `Want me to include what you already have?`
- Intro, chosen by which scopes are present:
  - GitHub-account rows only: `Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone.`
  - This-Mac rows only: `This Mac is already set up to reach GitHub, and I checked that what's here works. I can build on it, or leave it alone and set the rest up around it.`
  - Both: `You already have some of this: spaces of your own on GitHub, and a working connection on this Mac. I can build on what's here, or leave it alone and set up the rest around it.`
- Card 1 label (`scope: "personal"`): `Already in your GitHub account`
- Card 2 label (`scope: "machine"`): `Already on this Mac`
- Row title and row caption: the CLI's `title` and `detail`, verbatim (Appendix D holds the required strings)
- Cleared-row caption, revealed under the row: the CLI's `decline_detail`, verbatim. A missing one renders no caption rather than invented copy.
- Quiet line under the cards, always present: `Nothing you already have is changed. Setup only adds what's missing.`
- Leading action: `Not now`
- Primary action: `Include what I have`
- Primary disabled hint, every row cleared: `Choose something to include, or select Not now.`
- Re-plan progress card, after either action: `Checking what that means…`

**The two ideas are held apart on purpose.** The row caption is the CLI's specific found fact ("I checked this, it works, I'm leaving it alone, one thing gets added"). The quiet line is the app's general guarantee, structurally true for every `action: "create"` + `reversible: true` row. Never merge them: the never-destroy promise must not depend on the CLI getting a sentence right.

**Declining is never terminal.** `Not now` re-plans without those tokens and setup carries on to Detect. The offer survives in the menu bar as the `connection-offer` notice (§1.8). Without that row the CLI's decline sentence is a lie.

## 2.3 Choose copilots

- Eyebrow: `Step 4 of 10`
- Title: `Which copilots do you want?`
- Intro: `Pick the copilots you'd like Control Tower to set up and keep current.
  Anything your team hasn't made available to you is shown, but greyed out.`
- Section title: `Copilots`
- Disabled-row tooltip / help: `Your team hasn't made this copilot available to you.`
- Validation (all unchecked): `Pick at least one copilot to continue.`
- Buttons: `Back` / `Continue`

## 2.4 Departments

- Eyebrow: `Step 5 of 10`
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

- Eyebrow: `Step 6 of 10`
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

- Eyebrow: `Step 8 of 10`
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

- Eyebrow: `Step 9 of 10`
- Title: `Making sure everything's current`
- Intro: `The only success here is everything actually being up to date.`
- Loading: `Checking your setup...`
- Result (calm, not celebratory): `Everything checks out.` Permitted **only** when the completion rule in §2.10 passes. If it does not, Verify renders §2.10 instead. There is no hedged middle wording.
- Buttons: `Continue`

## 2.8 Done

- Eyebrow: `Step 10 of 10`
- Title: `You're set up.`
- Intro: `Control Tower now lives quietly in your menu bar. When it has nothing to say,
  it says nothing. That quiet icon means everything's current.`
- Callout: `When you're added to a new department later, it'll show up in the menu bar
  as "Available to join," whenever you're ready.`
- Primary button: `Done`

## 2.9 Holding (the honest terminal, never a dead end)

Holding is seven variants, not one screen. The variant is chosen by **who owns the fix**, never by what went wrong. Three of the seven are not failures at all: H4 is invariant #3 working correctly (setup found something the person already owns and refused to overwrite it), H5/H6 are patience, and H7 is a request only the person can answer. Only H2 and H3 are faults.

**H6 is patience for a genuine end user, but the owner test can still reclassify it.** The `no-company-app` cause (the org's sign-in isn't finished) has exactly one real, already-known fix today: give this Mac the org's GitHub App sign-in ID (`cc config set github_app.client_id <id>`). Whether "you" can do anything about that depends entirely on whether "you" are the org's own admin, standing at the very Mac that ran its standup — and that is knowable, locally, with no network and no CLI role token (none exists, and none could: at the moment H6 fires there is no credential yet for one to ride on). Admin mode's own standup already writes a non-secret brief on this Mac (`~/Library/Application Support/CopilotControlTower/standup-brief.md`/`.json`) the instant it runs; its mere presence says "the org's admin set this Mac up," and its `github_app.client_id` field (typed in by the admin's own hand during standup, and not a secret — GitHub publishes a Client ID; only the App's client *secret* is sensitive) supplies the exact command with no guessing. So: brief absent -> ordinary H6 below, unchanged. Brief present AND its client id readable -> the owner test flips this to H7 (§2.9's own words: "the fix is yours, it is a real fix and not a decision, and you can do it right here" is exactly as true of a terminal command as of a GitHub permission grant), reusing H7's existing eyebrow/tint/badge rather than inventing an eighth variant, with its own title/intro/sheet (below). Brief present but the client id isn't readable -> stays the ordinary H6 too: never assert a fix that isn't actually verified. The other two H6 causes (`onboard-unavailable`, `secret-store`) have no known concrete local fix today, so they stay H6 regardless of who's reading the screen.

| # | Variant | Eyebrow | Title | Tint (visual-system §2.2) |
|---|---|---|---|---|
| H1 | Not installed | `ONE MORE PIECE TO INSTALL` | `The setup helper isn't installed yet` | `setup-needed` neutral |
| H2 | Can't read your setup | `SETUP PAUSED` | `I can't read your setup, so I've paused` | `cli-unreadable` red |
| H3 | Couldn't finish a part | `SETUP PAUSED` | `I couldn't finish one part of setup` | `needs-attention` orange |
| H4 | Something is already yours | `ONE THING TO DECIDE` | `Something here is already yours` | `accent` blue, never orange |
| H5 | Waiting | `WAITING FOR THE NETWORK` | `I'll pick this up when you're back online` / busy: `Something else is updating right now` | `waiting-for-network` neutral |
| H6 | Waiting on your organization | `WAITING ON YOUR ORGANIZATION` | `Your organization has a bit left to set up` | `it-config-incomplete` neutral |
| H7 | Something only you can do | `ONE THING ONLY YOU CAN DO` | `Setup needs one permission from you` | `signed-out` blue, glyph `key` |

**Why H7 is its own variant.** Run the owner test on the other six: H1's owner may not be the person and its fix is outside the app; H2 and H3 name no owner and end in support details; H4's owner is the person but its frame is "nothing is wrong, decide about your own content"; H5 is time and H6 is the organization. None of them carries *the fix is yours, it is a real fix and not a decision, and you can do it right here*. That is H7, and it is the tone SOUL §7 already names: direct, singular, the one thing only he can do.

**Intro lines, by cause** (the reason is never a token, never raw CLI text as a headline):

| Cause | Variant | Intro |
|---|---|---|
| CLI not found on this Mac | H1 | `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.` |
| CLI wouldn't start | H2 | `The setup helper is on this Mac, but it wouldn't start just now, so I won't guess.` |
| Unreadable response | H2 | `I can't read what's already on this Mac right now, so I won't guess.` |
| Versions don't match | H2 | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` |
| Can't confirm it's safe (fails closed) | H2 | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` |
| Unmapped CLI stop | H2 | `Something stopped me from reading your setup, so I won't guess.` |
| Your own space isn't recognized | H4 | `One of your own spaces on GitHub is set up in a way I don't recognize, so I left it exactly as it is.` |
| This Mac's connection couldn't be confirmed | H4 | `This Mac already has a GitHub connection I didn't set up. I checked it, couldn't confirm it's safe to build on, and left it exactly as it is.` |
| Settings here weren't set up by me | H4 | `I found settings on this Mac that I didn't set up, so I left them alone.` |
| Your unsaved work is in the way | H4 | `Some of your own unsaved work is in the way of an update, so I left it alone.` |
| A GitHub space couldn't be confirmed | H3 | `GitHub didn't confirm one of your own spaces, so I stopped before changing anything.` |
| This Mac's key couldn't be set up | H3 | `I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed.` |
| Codex Copilot didn't finish | H3 | `I couldn't finish adding Codex Copilot on this Mac.` (+ ` Everything else finished.` only when materialize did not block) |
| Setting up didn't finish | H3 | `Setting things up on this Mac didn't finish. Nothing that was already here was changed.` |
| Couldn't confirm everything is current | H3, title `I couldn't confirm everything's current` | the tray's own per-status sentence (§1.1), verbatim |
| Offline | H5 | `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` |
| Something else is updating | H5 | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` |
| Organization setup unreadable | H6 | `I couldn't read your organization's setup from GitHub, so I've paused.` |
| Organization sign-in not set up (this Mac isn't the org's admin, or the admin's own brief has no readable sign-in ID) | H6 | `Your organization hasn't finished setting up sign-in yet.` |
| Shared store not ready | H6 | `Your organization's shared store isn't ready for this Mac yet.` |
| GitHub hasn't been asked for a permission | H7 | `Setup gives this Mac its own key so it can reach GitHub safely. Adding that key needs a permission GitHub hasn't been asked for yet, and you're the only one who can give it.` |
| Organization sign-in not set up, but this Mac's own admin standup already ran here (title: `Setup needs your organization's sign-in ID`) | H7 (self-serve) | `Your organization hasn't finished setting up sign-in yet. I can see this Mac already set up your organization, so this one's yours to finish: your organization's sign-in already has its own ID, and this Mac just hasn't been given it.` |

**H4 only:** the card `What I left alone` (one row per CLI review item, the CLI's own detail verbatim) and the caption `Nothing was changed, moved, or removed.`. The confirmation after `Keep what I have` is **always §2.10**, never a resolved-sounding screen: H4 is reachable only from `result: "blocked"`, so the completion rule can never pass at that moment. The old `Kept as it is` confirmation is withdrawn.

**H6 only (Defect 1a):** a footer caption, `Whoever looks after your Mac can pick this up from here.`, and — the same call §2.10 already made for "Here's where that leaves you" — `Copy details for support` is H6's PROMINENT primary, not a buried disclosure: whoever actually reads this screen has exactly one real action (tell their admin, with the details attached), so the handoff is the explicit action rather than an implication. `Check again` and `Continue in the menu bar` both move to the leading row.

**H7 self-serve only:** no interactive flow exists here (unlike the GitHub permission grant), so it follows H1's own discipline instead: the body never contains the command, and the primary, `Show me the command`, opens a sheet that does (`Giving this Mac your organization's sign-in ID` / "This is one command for whoever set up this Mac. If that's you, paste it into Terminal. It only tells this Mac the ID your organization's sign-in already has; it changes nothing else." / block label `The step` / `Copy this step` / `Done`, closing the sheet and re-checking once automatically, exactly like §2.9.2/§2.9.3's own sheets). Leading actions: `Continue in the menu bar` and `Check again`.

**Actions.** `Try again` (primary: H2, H3, H5) · `Check again` (H1, H4, H6, H7 self-serve; nothing failed, so "try" would overstate it) · `Continue in the menu bar` (all seven; never marks setup complete) · `Show me how to install it` (primary: H1) · `Keep what I have` (primary: H4) · `Let setup manage it` (H4, only when the CLI declares consent for that gate) · `Include what I already have` (H4, existing return path) · `Copy details for support` (primary: H6) · `Grant this on GitHub` (primary: H7) · `Show me how to grant it` (H7, **only** when the CLI reports it cannot drive the grant itself) · `Show me the command` (primary: H7 self-serve) · `Use a different organization` (H6 and H7 self-serve, **only** when the hold was reached from §2.1.1; returns there with the field populated). On a repeat of the identical hold, add one caption: `Still the same. Nothing changed.`

**Why H6 needs a way back.** `Acme` and `Acme-Co` can both be real organizations on GitHub. Type the first when you meant the second and H6 is truthful about what it found and useless about what to do: you are told your organization hasn't finished setting up sign-in, and you wait on an admin with nothing to fix. `Use a different organization` exists for that one case and appears nowhere else. It is not a retry, because nothing failed. It is the correction of an answer given two screens earlier, and it costs one keystroke because nothing was persisted. Returning shows §2.1.1's second intro variant when the name came from this Mac's standup brief, and its first in every other case.

**A CLI-authored message is never a headline.** It appears under `What setup found:` (when the CLI wrote it for a person) or only inside the support details (when it names machinery). It is never concatenated into an app sentence.

### 2.9.1 Details for support (collapsed, on H2 / H3 / H4 / H6 / H7 / §2.10)

- Disclosure label: `Details for support` (collapsed by default, never self-expanding)
- Expanded caption: `Send this to whoever looks after your Mac. It has nothing private in it.`
- Copy affordance: `Copy details` / confirmed `Copied`
- Block, one label per line, technical terms correct and expected here: `Copilot Control Tower <version> (<build>)` · `Setup helper: <path>` · `Report format: <schema_version>` · `Step: <stage id>` · `Result: <result>` · `Code: <error code>` · `Message: <verbatim>` · `Recorded: <yyyy-MM-dd HH:mm>`
- Omit any line the app cannot fill. Never print `unknown`. `Recorded:` is the product's one sanctioned timestamp, because it is a past fact for IT, not a promise to the user.

### 2.9.2 Installing the setup helper (the sheet behind H1's primary)

- Title: `Installing the setup helper`
- Intro: `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.`
- Block label: `The steps` (the documented install commands, mono block, never wrapped into prose)
- Copy affordance: `Copy these steps` / confirmed `Copied`
- Secondary: `Open the install guide ›`
- Primary: `Done` (closes the sheet and re-checks once, automatically)
- The H1 body itself never contains a command, a path, or the CLI's name.

### 2.9.3 Granting the permission (the sheet behind H7's primary)

Verbatim reuse of §2.5.1's device-flow grammar, which the person completed two steps earlier at Connect GitHub. Only the title and the success line differ.

- Title: `Grant the permission`
- Intro: `GitHub will ask you to confirm this. Copy the code below, open the page, and paste it in.`
- Code label: `Your code`
- Copy affordance: `Copy code` / confirmed `Copied`
- Primary: `Open the GitHub page`
- Waiting line (no countdown, no timer): `Waiting for you to finish in your browser...`
- Granted: `Granted. Picking up where I left off.`
- Denied: `That was declined.` + `Try again`
- Expired: `That code expired.` + `Get a new code`
- Different account: `GitHub confirmed a different account, so nothing changed.` + `Try again`
- Permission not granted: `GitHub did not grant the permission this Mac needs.` + `Try again`
- Timeout: `That took too long.` + `Get a new code`
- Dismiss buttons: `Cancel` (while pending) / `Done` (once granted)
- Quiet caption on H7 itself, above the footer: `I'll take you to GitHub to grant it. Nothing on this Mac changes.`

**The fallback sheet**, behind `Show me how to grant it`, shown only when the CLI reports it cannot drive the grant:

- Title: `Granting the permission by hand`
- Intro: `This is one command. If you're comfortable in Terminal, paste it there. If you're not, copy it and send it to whoever looks after your Mac.`
- Block label: `The step` (mono block, never wrapped into prose): `gh auth refresh -h github.com -s write:public_key`
- Copy affordance: `Copy this step` / confirmed `Copied`
- Primary: `Done` (closes the sheet and re-checks once, automatically)
- The H7 body itself never contains a command, a path, or the phrase `permission scope`.

**Why a button and not a copyable command.** The owner of this fix is the person and can be nobody else: it is a permission on his own GitHub sign-in, which IT cannot grant without sitting at his Mac signed in as him. §2.9.2 exists for the opposite case and says so in its own intro; reusing it here would route the work to an actor who cannot perform it (invariant #5). The action is additive and reversible, since permissions can be withdrawn on GitHub at any time. The app implements no auth: it calls a CLI verb, renders the code and the page, and hands the device code back, exactly as the Connect GitHub step already does (invariant #1).

## 2.10 I stopped, and here's what that means for you

The pattern every terminal confirmation in the wizard falls back to. It exists because a calm screen over an unfinished setup is worse than an obviously broken one: the person walks away believing they are done.

**The completion rule.** A screen may use resolved language, meaning *kept*, *done*, *set up*, *ready*, *checks out*, *everything*, or *all*, only when all four of these hold of the report it is rendering:

1. `result` is `applied` or `ready`. Never `changes-required`, never `blocked`.
2. No entry in `stages` has `result: "blocked"`.
3. Every stage in `onboard.schema.json`'s `ecosystemStage.stage` enum appears in `stages`. A stage the report never mentions counts as not done; `SetupProgressState.resolveStageRows` already computes exactly this and calls it `.neverReported`.
4. The sentence describes only what the report proves. A confirmation may resolve **the decision the person just made**; it may never resolve **setup** on the strength of that decision.

If any one of the four fails, the screen renders this section instead. The app never softens a failing condition with a gentler adjective; it switches patterns. Rule 4 is the one that catches the class of bug rather than the instance: the withdrawn `Kept as it is` was true about the decision and false about setup, and it printed only the true half.

- Eyebrow: `SETUP ISN'T FINISHED`
- Title: `Here's where that leaves you`
- Intro, after a decision the person just made: `I left your own things exactly as they were. Setup stopped there, though, so some of this isn't set up yet.`
- Intro, reached any other way: `Setup stopped partway, so some of this isn't set up yet. Nothing that was already on this Mac was changed.`
- Card 1 label: `What works now`. Empty body: `Nothing yet. Setup stopped before anything was put in place.`
- Card 2 label: `What doesn't work yet`. If this card would be empty, the rule passed and this screen must not render at all.
- Quiet line under both cards: `Nothing you already had was changed, moved, or removed.`
- Repeat caption: `Still the same. Nothing changed.`

**Row copy, keyed on the CLI's `stage` enum.** A closed app-authored set selected by a CLI token, the same discipline §1.2's reason table uses. Never the stage's `detail`, never the stage id, never a gerund.

| `stage` | `What works now` | `What doesn't work yet` |
|---|---|---|
| `organization-handoff` | `Your organization's shared setup came through.` | `Your organization's shared setup hasn't come through.` |
| `personal-packages` | `Your own spaces on GitHub are ready.` | `Your own spaces on GitHub aren't ready yet.` |
| `device-ssh` | `This Mac can reach GitHub on its own.` | `This Mac can't reach GitHub on its own yet.` |
| `layer-manifest` | `Your copilots are connected together.` | `Your copilots aren't connected together yet.` |
| `secret-store` | `The integrations your team shares are ready.` | `The integrations your team shares aren't ready yet.` |
| `codex-plugin` | `Codex Copilot is set up on this Mac.` | `Codex Copilot isn't set up on this Mac yet.` |
| `materialize` | `Your copilots are in place on this Mac.` | `Your copilots aren't in place on this Mac yet.` |
| `doctor` | `Everything checked out as current.` | `I couldn't confirm your copilots are current.` |

A stage that never ran and a stage that ran and failed take the same line. The difference is invisible to the reader and belongs in the support block.

**No fraction, ever.** No "3 of 8 done", no bar, no ring, no percentage. A fraction answers a question the person did not ask: five trivial stages done and three load-bearing ones missing scores the same as the reverse, so it cannot tell them whether they can use their copilots. Hard rule 7 already bans percentage-as-a-promise, §2.6 permits `Part N of M` only as in-flight phase position and never as an outcome, and §3.12 settled that even Earl gets a plain count and no score. Worst of all, a fraction invites them to judge severity, which is the judgement this product refuses to hand them. The two named capability lists carry everything a fraction would, in words they own.

**Actions.**

- Caption above the footer: `Whoever looks after your Mac can pick this up from here.`
- Primary: `Copy details for support` / confirmed `Copied` (the clipboard carries exactly §2.9.1's block, unchanged)
- Leading: `Try again`, then `Continue in the menu bar`
- **One branch:** when the current plan still carries ask rows (any inventory item with `reversible == true`), the primary becomes `Include what I already have` and `Copy details for support` moves to the leading row. A user-owned way forward always outranks a handoff.

`Details for support` (§2.9.1) stays collapsed and never self-expands. Prominence comes from the button, not from forcing the block open: whoever needs to hand it over copies it in one click without reading a line of it, and whoever wants to inspect it still can. `Continue in the menu bar` never marks setup complete, and the tray keeps rendering what the CLI reports, which by construction is not `Everything is set up.` That was the original failure: a calm surface over an unfinished machine.

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
  - `Setup needs permission to work in your GitHub organization. It creates your shared
    repositories and sets up your teams and their access, so the GitHub command-line
    tool needs two permissions, called scopes: repo and admin:org. The next step checks
    for these and gives you the exact command to grant them if they are missing.`
  - `Review protection needs a paid GitHub plan. Setup asks GitHub to require a review
    before your shared setup files change. For private repositories, GitHub only offers
    that on a paid plan. On the free plan, setup still finishes and your spaces are
    created, they just won't have review protection until you upgrade.`
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
- **Invalid-org refusal (inline, on the organization name field):** the org name is an
  EXISTING GitHub identifier, used verbatim, case preserved, never lowercased or
  slugified; the refusal enforces GitHub's own organization-name rule instead of the
  department-name slug rule below: `That doesn't look like a GitHub organization name.
  Use letters, numbers, and single dashes.`
- **Invalid-slug refusal (inline, on the offending department field):** `Give this
  department a name using letters, numbers, and dashes.`

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
- **Point users at the app** (Defect 2, completion-rule violation: the withdrawn copy
  here — "it sets them up from what you just built... they'll see the departments
  they're on" — was a specific, falsifiable prediction about a machine this run never
  tested; the Setup check above only reads GitHub, never a user's own Mac, so this card
  may only claim what was actually proven): `Your team installs Copilot Control Tower
  themselves. The setup check above only confirmed your organization's spaces on
  GitHub, not any one person's Mac, so the first person who signs in is the real test
  of that.`

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
| `Here's where that leaves you.` | `Kept as it is.` (while five stages never ran) |
| `This Mac can't reach GitHub on its own yet.` | `3 of 8 done` |
| `Setup needs one permission from you.` | `Your token is missing the admin:public_key scope.` |
| `Which organization are you with?` | `Set github_app.org to your organization slug.` |

# Appendix B: Words banned from every user surface

`MDM`, `entitled` / `entitlement` (as a bare word to Bob), `repo` / `repository` (on a
Bob surface; "your team's shared space" or "address" instead), `product` (meaning a
copilot), `component` (as a section label; fine in prose), `YAML`, `daemon`, `parse`,
`schema`, `token`, `scope` (as a permission), `OAuth`, `SSH`, `alias`, `device` (say
"this Mac"), `rank`, `manifest`, `package`, `tier`, raw `git` / `serde` / signature /
watchdog strings, `Aviator` (the dead codename). And no em-dashes, anywhere.

One explicit permission: **`key` is allowed**, and is the settled word for what this Mac
is given (§2.6 `Giving this Mac its own key`, H7, §2.10's `device-ssh` rows).

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

# Appendix D: CLI strings and contract additions the adopt-and-honesty change requires

Detect rows, ask rows, and framed Holding details are printed straight from the CLI, so those strings are user-facing copy and must obey the same closed vocabulary as the app's own. `cc/core/ecosystem/ssh_identity.py` and `cc/commands/onboard.py` currently emit `SSH`, `alias`, `device`, and raw GitHub logins on surfaces Bob reads. These are the required replacements.

## D.1 Required string replacements

| Today | Required |
|---|---|
| item title `This device's GitHub SSH access` | `Your Mac's connection to GitHub` |
| adoption `detail`: `Your existing {alias} alias already works and signs in as {login}. I'll leave it exactly as it is.` | `This Mac already connects to GitHub, and I checked that it works and that it's signed in as you. I'll leave that exactly as it is and add the one connection it's still missing.` |
| `decline_detail`: `Without this, the {alias} alias won't be set up, and this device won't have everything it needs. Your existing {alias} alias is never touched either way.` | `Without this, this Mac keeps one of the two GitHub connections setup uses. Setup carries on, and I'll offer this again from the menu bar whenever you're ready.` |
| `The existing {alias} SSH alias could not confirm a GitHub login, so it was left exactly as it is.` | `This Mac's existing GitHub connection didn't confirm who it signs in as, so I left it exactly as it is.` |
| `GitHub could not confirm the signed-in account, so the existing {alias} SSH alias was left exactly as it is.` | `GitHub didn't confirm who you're signed in as, so I left this Mac's existing connection exactly as it is.` |
| `The existing {alias} SSH alias signs in as a different GitHub account ({login}), so it was left exactly as it is.` | `This Mac's existing GitHub connection signs in as a different account ({login}), so I left it exactly as it is.` |
| `The existing {alias} SSH alias does not resolve to {host}, so it was left exactly as it is.` | `This Mac's existing GitHub connection points somewhere other than GitHub, so I left it exactly as it is.` |
| `The existing {alias} SSH alias could not confirm real repository access, so it was left exactly as it is.` | `This Mac's existing GitHub connection couldn't reach your spaces on GitHub, so I left it exactly as it is.` |
| `Malformed Copilot-managed SSH config block.` | `I don't recognize how this Mac's GitHub connection is written down, so I left it exactly as it is.` |
| `Only one half of the device SSH keypair exists; setup did not replace it.` | `Part of this Mac's own GitHub key is missing, and I won't replace what's there.` |
| `Every alias this device needs already works. Nothing was changed.` | `This Mac's connections to GitHub already work. Nothing was changed.` |
| `The device SSH identity is ready.` | `This Mac has its own key for GitHub.` |
| `The device SSH identity can be completed without copying a private key.` | `This Mac can be given its own key for GitHub, without copying anything from another Mac.` |
| `GitHub could not list SSH keys for the authenticated account.` **(403 or 404)** | `Your GitHub sign-in doesn't include permission to add this Mac's key.` |
| `GitHub could not list SSH keys for the authenticated account.` **(any other failure)** | `GitHub didn't answer when I asked about this Mac's keys.` |
| `GitHub returned an unreadable SSH key response.` | `GitHub's answer about this Mac's keys wasn't something I could read.` |

The third row deliberately keeps `({login})`. It is the one fact that lets the person recognize the situation, it is their own data, and a second forgotten account is the most common real cause.

Every replacement above is under 200 characters, single-line, and free of `{`, `}`, `<`, `>`, `Traceback`, `Error:`, `Exception`, `/Users/`, and `.py:`, so all of them pass `HoldingInfo.isPresentable` and can be framed under `What setup found:` without being suppressed.

## D.2 Contract additions

| Verb | Addition | Values | Why the app needs it |
|---|---|---|---|
| `onboard --json` | on the `device-ssh` stage, `registration: "not-permitted"` together with `result: "blocked"` and `config: "planned"` | new value alongside `registered` / `missing` / `not-checked` | Splits a missing GitHub permission (H7, the person's own fix) from a generic key-listing failure (H3, nobody's). `registration` is already `{"type": "string", "minLength": 1}` in `onboard.schema.json`, so this needs **no schema change and no version bump**. The app reads an enum token, never prose. |
| `auth grant --json` | starts the permission grant and returns `{user_code, verification_uri, device_code, interval}`; `--poll --device-code <code>` polls it; reports `unavailable` when it cannot drive the flow | (none) | H7's primary action, and the only thing that reveals `Show me how to grant it`. Same open seam as decision D-3-M3 (the wizard's sign-in device-flow verb); close both in one change. |

The app's gate table in `holdingInfo(forBlockedOnboard:)` gains exactly one branch, read from a CLI-emitted enum token and never sniffed from a prose string, exactly as every existing H4 branch already is: for `case "device-ssh"`, test `registration == "not-permitted"` (H7) before the existing `config == "held" || key == "incomplete"` test (H4), falling through to H3.

## D.3 The two app-side bugs this copy depends on

Both are in `native/wizard.swift`. Without both fixes, §2.2.1's machine-scope row renders nothing and the dead end persists in a new form.

**Bug 1: `personalOnboardQuestion` drops the machine-scope row.** It filters `scope == "personal"`, and the CLI's SSH row is `scope: "machine"`, so the row is silently dropped and the offer never appears. The scope filter must go. Ask rows are every inventory item with `reversible == true`, in the CLI's order. Review rows are every item with `action == "review"`, in the CLI's order. Both are then grouped into §2.2.1's two cards by `scope`, and the scope word itself never reaches the screen.

**Bug 2: `componentId(fromPersonalInventoryId:)` returns `nil` for `device-ssh`.** It strips a `personal-` prefix, which the SSH item's id (`device-ssh`) does not have, so the consent is dropped, the apply writes nothing, and the offer repeats forever. The token map is `personal-<component>` to `<component>`, and **`device-ssh` to `ssh`**. `ssh` is the exact token `ensure_machine_ssh_identity` checks for, and `build_ecosystem_onboard_report` already forwards `adopt_existing` to `ssh_fn` at both plan and apply, so no CLI plumbing is missing; only the app's token is. This is the highest-risk line in the change, because it fails silently and looks like the CLI's fault.

## D.4 Ordering note, already correct

`performDetect` asks the question **before** the blocked-guard, which is right and must stay that way. A plan that is blocked purely because an unrelated item needs review must still surface the question rather than dropping it behind Holding's review-only card. That is the old dead end, and the ordering is what prevents it.

# Appendix E: The organization question, contract additions and carriers

§2.1.1 asks a person for a value. That single fact changes who owns three failures the CLI currently collapses into one code, and it puts a fourth on the person's own field. `core/ecosystem/bootstrap_config.py`'s `fetch_org_client_id()` fails open to `None` on every network, format, and mismatch problem alike, and `commands/auth.py`'s `_resolve_client_id()` renders all of them as `no-company-app`. Its docstring's reasoning, that none of these are actionable by the person signing in, was true before this screen existed and is false now.

## E.1 Contract additions

| Verb | Addition | Why the app needs it |
|---|---|---|
| `auth login --json` | The bootstrap file's `org` comparison folds case. The value is still sent to GitHub exactly as published. | A person told `Acme-Co` types `acme-co`. Today `data.get("org") != org` is an exact match, so that fails open and renders H6, telling them their organization hasn't finished setting up sign-in when it has. This is the most likely single input error in the flow, and it currently lands on the variant reserved for "not your fault, wait." GitHub logins are case-insensitive and unique by fold, and commit `401b585` already settled that the name is used verbatim and never lowercased. |
| `auth login --json` | New error code `org-not-found`, from an unauthenticated check that the organization resolves on GitHub at all. **An inconclusive or rate-limited probe degrades to `no-company-app`, never to `org-not-found`.** | Separates "the name I was given isn't an organization on GitHub" (§2.1.1's own field, one keystroke) from "your organization hasn't published its sign-in yet" (H6, their admin's). Without it every typo becomes an indefinite wait on someone with nothing to fix. The fail direction is load-bearing: telling someone their real organization doesn't exist is worse than making them wait, and the unauthenticated GitHub rate limit is shared by everyone behind one corporate address. |
| `auth login --json` | New error code `network-unavailable` for a transport failure fetching the bootstrap file. | Today an offline Mac is told its organization hasn't finished setting up sign-in. That is a fabricated state, which hard rule 6 forbids, and H5 already exists for it. |

## E.2 The carriers, so §2.1.1's intro is true

§2.1.1 tells the person the name is on the download page and in the email. Both must carry it, or the sentence is a lie and the screen is a dead end with better manners.

**`landing-site.md` §3.1, directly under the three install steps:**

- Block label: `When Control Tower asks which organization you're with`
- The name, copyable: `Acme-Co`
- Copy affordance: `Copy` / confirmed `Copied`
- Quiet line: `Copy this and paste it in when Control Tower asks. It's the only thing you'll need to type.`

**The invitation email (walkthrough screen 1.1), one line near the download link:** `When it asks which organization you're with, the answer is Acme-Co.`

The organization's name on GitHub is not a secret and is not org configuration in the sense `landing-site.md` §1's admin bullet forbids: the page already prints "Signed by `<Org>`", and the file it names is public by construction. The page still carries no admin materials, no client secret, and no download of the admin build. (Owner confirmed.)

## E.3 App-side and admin-side plumbing this copy depends on

- `holdingInfo(forExit2Code:)` gains `case "org-required": return nil`, beside the existing `signed-out` case, and `routeCliError` enters the organization question rather than Holding when `nil` comes back from that code.
- `CliClient.authLoginInitiate()` and `authLoginPoll(deviceCode:)` both take an optional organization and pass `--org`. The poll needs it too: `build_auth_poll_report` re-resolves the client id on every call.
- `LocalAdminSignal` gains `standupOrgName`, reading `org` from `standup-brief.json` exactly as `standupGitHubAppClientID` reads `github_app.client_id`: trimmed, `nil` on any read failure or blank field, never a fabricated placeholder.
- **Admin standup writes `github_app.org` when it writes the brief.** Then the admin's own Mac never reaches `org-required` at all, and §2.1.1's silent brief branch is only a recovery path for Macs whose standup predates that change.
- The user wizard has no text field today. This is its first. Admin's organization field (§3.7) is the visual reference, and its `orgSlugTouched` gating is the validation-timing reference.

## E.4 Open contract question

This appendix assumes the app persists the pointer with `cc config set github_app.org <name>`, which is what `commands/auth.py`'s own docstring names as the app's job ("the app sets this once via `cc config set github_app.org <org>` after collecting it during onboarding"), so the CLI already anticipated this screen. But `cc config set` prints human text and has no `--json` output, so the app can read only its exit code. Whether that is acceptable under the versioned contract, or whether persistence needs a machine-readable verb of its own, is unresolved and owner-owned. The copy does not depend on the answer: no string claims the value was saved, and the only failure path ("the pointer could not be written to this Mac") routes to an existing H2 intro.

---

*Copy deck complete. Every placeholder string in `control-tower-interaction-spec.md` §8
now has a final value here. Route to uids (Stage 3 visual system) for how these strings
sit in the six popover regions and the two integration registers, and back to the
implementer to replace the current `native/*.swift` copy (notably the "CSE components,
not products" and "because you're entitled" strings, which leak vocabulary Bob would not
use).*
