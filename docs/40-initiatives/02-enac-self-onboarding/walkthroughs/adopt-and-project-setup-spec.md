# Adopt existing content, and project setup

## Service outcome

A non-technical person whose GitHub account already holds their own Claude or Codex content is **asked** instead of refused. Setup names what it found, offers to include it, guarantees in writing that nothing existing is touched, and lets the person decline without reaching a dead end. The private note that makes inclusion possible is written by the CLI on approval; nobody authors anything by hand, ever.

The same person is shown **every** project on this Mac that can have copilots, not one of them, and not only when a checkbox about a second copilot happened to be ticked. Granting the folder to watch is a normal step of setup with its own place in the roadmap, and it is reversible.

From then on, projects the person **creates** get their copilots without being asked, because there is nothing of theirs to protect and no decision only they can make. Projects that **already existed** are always asked about, because something of theirs is already there. The person can see that automatic setup happened, and undo it per project.

Jobs to be done:

- When setup finds content I already own, I want to be asked whether to include it, so I can move forward without risking anything I already have.
- When I have projects on this Mac, I want to see all of them and set them up in one pass, so I do not have to hunt one project at a time.
- When I create a new project, I want my copilots to already be there, so I never think about setup again.

## Service blueprint

| Stage | Person sees and does | Control Tower does | Failure and recovery |
|---|---|---|---|
| Find | Detect reports what is already here. | Renders the CLI plan's inventory verbatim. A private space holding the person's own content is no longer a refusal. | An unreadable plan still routes to Holding with the existing unreadable reason. |
| Ask | **One question first** replaces Detect inline, listing each space the CLI marked as a question, pre-selected. | Renders the CLI's question items. Writes nothing. | No question items means this screen never appears. |
| Reveal the cost | Clearing a selection reveals, under that row, what declining it costs. | Renders the CLI's decline sentence for that item. | A missing decline sentence renders the row with no caption rather than invented copy. |
| Decide | **Include what I have** or **Not now**. | Sends the chosen set back and re-runs the read-only plan. Nothing is written yet. | A failed re-plan routes to Holding with **Try again**, which returns to the question. |
| Decline | Setup continues without those spaces, or Holding explains what cannot finish. | Renders the CLI's re-planned result. Holding now also offers **Include what I already have**. | Holding is never terminal: the question is always one action away. |
| Grant a folder | **Your projects** (step 7 of 10) asks for the one folder where projects live, or is skipped. | Approves that folder for bounded discovery and reads the projects inside it. | An unusable folder shows the CLI's blocked sentence next to the picker and keeps the step usable. |
| Choose projects | Every discovered project is listed with its own state, pre-selected where it can be set up, with **Select all** and **Select none**. | Renders the CLI's per-project state. Writes nothing during this step. | A project the CLI cannot set up safely is listed, honest, and unselectable. |
| Apply | **Set up** names a project phase and Done reports the count. | Applies the marker write, then the per-project setup, in the one place writes happen. | A per-project failure leaves that project listed as **Couldn't add it**, never stops the rest, and never partially claims success. |
| New project | Nothing, by design. The project simply works. | Applies the CLI's automatic policy for projects created since the folder was granted. | Nothing to protect means nothing to ask; a project with existing content falls back to being asked. |
| Discover it happened | A one-time notice the first time, a past-tense line in **What changed** every time, and a caption in **Your projects**. | Renders the CLI's record of automatic setups. | If the CLI reports nothing, the app claims nothing. |
| Undo | **Undo** on that project's row. | Sends the undo to the CLI, which removes only what it added and stops offering that project automatically. | If the person edited those files, undo is unavailable with an honest reason, never a destructive fallback. |

## Interaction specification

### One question first (inline over Detect)

Rendered exactly the way Holding is rendered: a `StepShell` over the Detect stage, adding no sidebar row and changing no step number, entered when the CLI's plan carries question items. The header tint is the accent blue, never Holding's orange, because this is an offer and not a pause.

- Eyebrow: **ONE QUESTION FIRST**
- Title: **You already have some of this. Want me to include it?**
- Intro: **Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone. Either way, nothing in them is changed, moved, or removed.**
- Card label: **Already in your GitHub account**

One row per question item, in the CLI's order, each a checkbox that starts selected:

- Row title, verbatim from the CLI: **Your Claude Copilot space**
- Row caption: **Your own content is already in here. I'll keep all of it and add a small note that says it belongs with your copilots.**
- Cleared row caption, revealed under the row, verbatim from the CLI: **Without this, Claude Copilot can't be set up on this Mac. You can include it later.**

One row per item the CLI marked for review instead of a question. It carries no checkbox, a trailing read-only label **Kept as is**, and a hand-raised glyph:

- Row title: **Your Codex Copilot space**
- Row caption: **I don't recognize how this space is set up, so I'll leave it exactly as it is.**

Quiet line directly under the card, always present: **Nothing existing was changed.**

- Leading action: **Not now**
- Primary action: **Include what I have**
- Primary disabled hint, when every row is cleared: **Choose something to include, or select Not now.**

Several components can be in this state at once, and each is decided on its own row. Claude, Codex, Knowledge, and CLI never share a fate here: the primary action includes exactly the selected rows, and every cleared row is treated as declined for this run. There is no all-or-nothing choice, and no row is hidden because another row is worse.

Microinteraction, clearing a row: trigger is the checkbox; the rule is that a cleared row is declined; the feedback is the CLI's decline sentence appearing under that row in 150ms with no layout jump elsewhere; the loop is that re-selecting removes the caption again. Nothing is sent to the CLI while the person is deciding.

Microinteraction, deciding: trigger is **Include what I have** or **Not now**; the rule is that the app sends the selected set to the CLI and re-runs the read-only plan; the feedback is the shared progress card with **Checking what that means…**; the destination is the Detect result screen when the plan can proceed, or Holding when it cannot.

### Detect, after a decision

Detect's existing **What Control Tower found** card gains the decided rows, using its existing glyph and label grammar:

- Included: action label **Include**, caption verbatim from the CLI, for example **Everything already in here will be kept, and it will be part of your copilots.**
- Declined: action label **Set aside**, caption verbatim from the CLI, for example **Left exactly as it is. You can include it later from the menu bar.**
- Review: unchanged from today, action label **Needs review**.

### Holding, when a decision leaves setup unable to finish

Unchanged in title, reason, and tint. It gains one leading action so the refusal can always be turned back into the offer:

- Leading actions: **Include what I already have**, then **Continue in the menu bar**
- Primary action: **Try again**

**Include what I already have** returns to the question with the previous selections intact. This is the only new affordance the screen needs; Holding stops being reachable by refusal and becomes reachable only by the person's own choice or by a genuine outside failure.

### Step 7 of 10: Your projects

A real step with a real sidebar row, **Your projects**, between Integrations and Set up. It is never conditional on a second copilot, and it is skippable without judgement. Every other step's eyebrow becomes **STEP N OF 10**.

- Eyebrow: **STEP 7 OF 10**
- Title: **Where do you keep your projects?**
- Intro: **If you build things on this Mac, Control Tower can set your copilots up inside each project too. Choose the one folder where your projects live. Control Tower looks only inside that folder, and never anywhere else on this Mac.**

Empty state, no folder chosen yet:

- Card label: **Your projects folder**
- Body: **No folder chosen yet. Nothing is being watched.**
- Action: **Choose folder…**

Granted state:

- Card label: **Your projects folder**
- Body, one row per watched folder: folder name, plus a trailing **Stop watching**
- Actions: **Add another folder…**
- Quiet line: **Control Tower looks only inside the folders listed here.**

Projects list, after a folder is granted:

- Card label: **Projects I found**
- Count line, from the CLI's summary: **12 projects found. 9 can be set up.**
- Group order: projects that can be set up, then projects that need finishing, then projects already set up behind a disclosure, then projects kept as is.
- Group actions: **Select all**, **Select none**
- Already-set-up disclosure label: **9 already set up ›**

| Project row state | Caption | Row control |
|---|---|---|
| Can be set up | **Copilot can be set up here.** | Checkbox, selected |
| Needs finishing on this Mac | **Set up here already, but not active on this Mac yet.** | Checkbox, selected |
| Already set up | **Already set up.** | None |
| Kept as is | CLI sentence, for example **Something's already here that I don't recognize, so I left it alone.** | None, trailing label **Kept as is** |

Empty list state, folder granted and nothing found: **No projects in that folder yet. Any new one you create will get your copilots automatically.**

- Leading actions: **Back**, then **I don't keep projects on this Mac**, then **Skip for now**
- Primary action: **Continue**

**I don't keep projects on this Mac** records the decline so the menu bar never offers this again, and confirms inline with **Got it. I won't ask about projects again. You can turn this on any time from the menu bar.** **Skip for now** leaves the offer available in the menu bar.

Nothing is written to a project during this step. The step collects a grant and a selection; the writes happen in Set up, where every other write happens, and where the copilots this project setup copies from actually exist on this Mac. The CLI states this per project with `can_apply_now: false` and the sentence the step renders under the count line: **Your projects get set up in the next step.**

### Step 8 of 10: Set up

The existing named-phase progress gains project phases, still with no time and no percentage:

- **Including what you already have…**
- **Setting up your copilots in 9 projects…**
- Per-project failure is collected, never fatal, and never retried silently.

### Step 10 of 10: Done

The projects card is no longer conditional on Codex. Its body is chosen by what actually happened:

- Projects were set up: **Your copilots are set up in 9 of your projects. Any new project you create in that folder gets them automatically.**
- Some project failed: **Your copilots are set up in 8 of your 9 projects. One needs another look, and it's waiting for you in the menu bar. Nothing existing was changed.**
- Step skipped: **You skipped projects for now. Point Control Tower at your projects folder any time from the menu bar.**
- Declined: the card is absent.

### Menu bar: the projects notice (Region 6)

Today the projects prompt sits in an `else if` behind the unsaved-changes prompt, and renders only the first project. That is replaced by sequential rendering: at most one **prompt** as today, and then, independently, the projects **notice**. The unsaved-changes prompt can no longer make projects invisible, and the closed action row in Region 5 stays closed.

Notice, one or more projects can be set up:

- One: **1 project can have your copilots. Nothing is added until you say so.**
- Several: **9 projects can have your copilots. Nothing is added until you say so.**
- Action: **Review projects**

Notice, no folder granted yet and not declined:

- **Building something on this Mac? I can set your copilots up in your projects too.**
- Actions: **Choose folder…**, then the quiet text action **Not on this Mac**

Notice, first automatic setup ever, shown once and never again:

- One project: **New projects get your copilots automatically now. I just set up Convoco.**
- Several: **New projects get your copilots automatically now. I just set up 12 new projects.**
- Actions: **Review projects**

Nothing else is added to the menu bar. There is no badge for projects, because a project waiting to be set up is an offer and not a fault.

### Menu bar: Your projects (drill-in)

The fuller list lives one level deeper inside the popover, using the same back-and-drill-in grammar **What changed** already uses. It is not a new window, not a modal, and not a sheet. Settings gains **Your projects** as the permanent home for the same list when Settings ships; until then the drill-in is that home.

- Back: **‹ Back**
- Title: **Your projects**
- Count line: **9 of 12 can be set up.**
- Group action: **Add all**
- Row: project name, its caption, and **Add**
- Footer actions: **Add another folder…**, **Stop watching this folder**
- Scrolls at a fixed maximum height, with the count line as the orientation cue. Projects already set up stay behind the **9 already set up ›** disclosure.

| Row state | Caption | Control |
|---|---|---|
| Can be set up | **Copilot can be set up here.** | **Add** |
| Needs finishing | **Set up here already, but not active on this Mac yet.** | **Finish setup** |
| Adding | **Adding…** | Quiet spinner, no time |
| Added | **Added. Your own files weren't touched.** | None |
| Set up automatically | **Set up automatically when you created it.** | **Undo** |
| Undone | **Left alone at your request.** | **Add** |
| Kept as is | CLI sentence | None, trailing **Kept as is** |
| Couldn't add | **Couldn't add it right now. Nothing existing was changed.** | **Try again** |

Empty state, everything is fine: **All 12 of your projects are set up.** with **Add another folder…** still available.

Empty state, no folder granted: **Control Tower isn't watching any folder yet. Choose the folder where you keep your projects and it will set your copilots up there.** with **Choose folder…**.

The drill-in uses per-row **Add** rather than the wizard's checkboxes because by this point the copilots exist on this Mac, so an add can be applied the moment it is asked for, and immediate application is the shorter path for a returning person. The CLI states which grammar is available with `can_apply_now`; the app never decides that for itself.

### Automatic setup for new projects

A project created inside a granted folder is set up without being asked. This is not the app deciding: the CLI marks the project `setup_policy: "automatic"`, and the app applies exactly what it is told, the same way it already silently associates a ready project with the person's private profile.

- The person perceives nothing at the moment it happens. There is no notification, no badge, and no toast. Silence is the success state.
- It is discoverable three ways: the one-time notice above, a past-tense line in **What changed**, and the **Set up automatically when you created it.** caption in **Your projects**.
- **What changed** line, from the CLI's record: **Set your copilots up in Convoco.**
- **What changed** group label, when the automatic list is non-empty: **Projects set up for you**
- Pinned reassurance in that group, reusing today's line: **Only your copilots' shared files were added. Your own work in these projects wasn't touched.**

Automatic setup applies only where there is nothing of the person's to protect and no decision only they can make. A newly created project with content that would collide falls back to being asked, and appears in the notice and the list like any other project that needs a decision. This is the whole distinction from behaviour 2: a project that existed when the folder was granted is always asked about, because something of theirs is already there.

Automatic setup works offline, because it copies from copilots already on this Mac, and it says nothing about the network.

### Undo

- Action: **Undo**, on the row of a project that was set up automatically
- Result: **Removed. Your own files were left alone, and I won't set this project up again unless you ask.**
- Unavailable: **You've changed these files since, so I'll leave them alone.** with no **Undo** control at all, never a disabled one with no explanation.
- Failed: **Couldn't undo that right now. Nothing was changed.** with **Try again**

Undo is one action, applied immediately, with no confirmation dialog, because it is itself the reversal of a reversible act and re-adding is one action away. The destructive-sounding half of the pair, deleting the person's own files, is never offered by any control in this spec.

### State coverage

The two new interactive controls, in every state. Where a state cannot occur, the reason is stated rather than omitted.

| State | Question row checkbox | Project row **Add** |
|---|---|---|
| Default | Selected, title and caption at full contrast | Bordered button, row caption **Copilot can be set up here.** |
| Hover | Row background lifts to the card's hover fill; cursor unchanged | Standard bordered hover fill |
| Focus | System focus ring on the checkbox, row caption read as its description | System focus ring on the button |
| Active | Checkbox mark animates in over 150ms, caption reveal follows | Button pressed fill, then the row switches to **Adding…** |
| Disabled | Not applicable: a question row is always answerable. The primary action carries the only disabled state, with the **Choose something to include** hint | Disabled while another add is in flight, hint **Finishing the last one first.** |
| Loading | Not applicable: the row holds a local decision and calls nothing | Quiet spinner replacing the button, caption **Adding…**, no time and no percentage |
| Error | Not applicable at the row: an error belongs to the decision, and routes to Holding | Caption **Couldn't add it right now. Nothing existing was changed.** with **Try again** |
| Empty | Not applicable: the screen only exists when there is at least one question item | Two empty states, defined above for the granted and non-granted cases |

Loading strategy: the question screen inherits an already-loaded plan and needs no loading state of its own; the re-plan after a decision uses the existing progress card with **Checking what that means…** because its duration is unknown; the projects list after granting a folder uses three skeleton rows, because its layout is known before its content is; per-row adds use an in-row spinner because only that row is changing; automatic setup shows nothing at all.

### CLI contract additions

Everything above is rendered from the CLI. The app holds one thing the CLI cannot know, the person's own choice, and sends it straight back.

| Verb | Addition | Values | Why the app needs it |
|---|---|---|---|
| `onboard --org … --json` | per-inventory-item `action: "ask"` | new value alongside reuse/create/migrate/repair/review | Turns today's refusal into a question. Applies when a private space holds the person's own content and no recognized marker, so inclusion is a pure addition. |
| `onboard --org … --json` | report-level `questions: [...]` | the ask items, in display order | The app renders the question screen when this is non-empty, instead of scanning for a state. |
| `onboard --org … --json` | per-item `adopt_token` | opaque string | What the app sends back for the rows the person selected. |
| `onboard --org … --json` | per-item `decline_detail` | one plain sentence | The cost revealed under a cleared row. The app never writes this sentence. |
| `onboard --org … --json` | report `result` for an ask-only plan | `changes-required`, never `blocked` | A question is not a refusal. `blocked` stays for genuine review and outside failures. |
| `onboard --adopt <tokens>` | new flag on plan and apply | comma-separated tokens | Carries the decision. Unlisted ask items are declined for this run, and the CLI re-computes what that costs. |
| `onboard --org … --apply --json` | per-item `action: "included"` / `"skipped"` with `detail` | plain sentences | Detect's decided rows and Done's summary. |
| `workspaces --all --json` | `discovery: {state, roots:[{name, path}]}` | `granted` / `not-granted` / `declined` | The menu bar can offer the folder grant instead of silently returning nothing when no folder is watched. Names are rendered; paths are only ever passed back to the CLI. |
| `workspaces --all --json` | per-workspace `setup_policy` + `policy_detail` | `ask` / `automatic` / `excluded` / `not-offered` | The app applies automatic setup and asks about the rest without computing which is which. |
| `workspaces --all --json` | per-workspace `can_apply_now` + `apply_blocked_detail` | boolean, plain sentence | Chooses the checkbox grammar in the wizard and the **Add** grammar in the menu bar. |
| `workspaces --all --json` | per-workspace `undo: {available, detail}` | boolean, plain sentence | Whether the row shows **Undo**, and the honest reason when it does not. |
| `workspaces --all --json` | `recently_set_up: [{name, detail}]` | past-tense sentences | The **Projects set up for you** group in **What changed**, and the one-time first-run notice, without holding state in app memory across launches. |
| `workspaces forget-root --path … --apply --json` | new verb | report with `root` | **Stop watching this folder**. Removes the grant. Deletes nothing. |
| `workspaces decline --apply --json` | new verb | report with `discovery.state: "declined"` | **I don't keep projects on this Mac** and **Not on this Mac**. Reversible from the same surfaces. |
| `workspaces revert --project … --apply --json` | new verb | report with what was removed and what was kept | **Undo**. Removes only files the CLI recorded as its own and whose recorded checksums still match, keeps everything else, and records the project as excluded from automatic setup. |

Two schema values the app must decode in the same change, or a healthy CLI will read as unreadable: the new inventory `action` values, and any new outcome value used for automatic project setup in the fan-out record.

### CLI strings the app renders verbatim

Detect rows and Holding reasons are printed straight from the CLI's `detail`, so those strings are user-facing copy and must obey the same closed vocabulary as the app's own. These are the replacements this change requires. None of the new strings contain an internal term or anything the person would have to open.

| Today | Required |
|---|---|
| `Existing user content has no recognized package manifest; nothing will be inferred or replaced.` | `Your own content is already in here. I'll keep all of it and add a small note that says it belongs with your copilots.` |
| `Existing package manifest is unfamiliar or invalid; nothing will be replaced.` | `I don't recognize how this space is set up, so I'll leave it exactly as it is.` |
| `Existing rank-10 package will be reused.` | `Already set up. Everything in here will be kept.` |
| `Confirmed-empty private repository can receive the rank-10 seed.` | `Empty and ready. I'll set it up for you.` |
| `Initialized the minimal rank-10 package in the confirmed-empty repository.` | `Set up and ready.` |
| `GitHub did not confirm rank-10 package initialization.` | `GitHub didn't confirm the change to your Claude Copilot space, so I stopped. Nothing existing was changed.` |
| `Existing private repository will be reused.` | `You already have this space. I'll use it as it is.` |
| `Repository does not exist and can be created privately.` | `You don't have this space yet. I'll create it privately for you.` |
| `GitHub could not confirm whether this repository exists.` | `GitHub couldn't confirm this space right now, so I won't guess.` |
| `A public repository already uses this name.` | `Something of yours is already using this name publicly, so I stopped. Nothing existing was changed.` |
| item title `Cli personal space` | `Your CLI Copilot space` |
| item titles `Claude personal space`, `Codex personal space`, `Knowledge personal space` | `Your Claude Copilot space`, `Your Codex Copilot space`, `Your Knowledge Copilot space` |
| item title `Copilot layers` | `How your copilots fit together` |
| `No layer manifest is in place yet. Setup will create the complete stack.` | `Nothing is connected yet. Setup will connect all of it for you.` |
| `The existing layer manifest is outside the user-owned setup area. Setup will leave it untouched.` | `Something is set up somewhere I don't manage, so I'll leave it untouched.` |
| `An existing layer manifest is unfamiliar. Setup will leave it untouched until it is reviewed.` | `I don't recognize an existing setting here, so I'll leave it untouched until it's looked at.` |
| `Existing Claude or Codex layers do not match a Control Tower-managed stack. Nothing will be replaced.` | `Your existing Claude or Codex setup isn't one I recognize, so I won't replace any of it.` |
| `The existing supported layers will be kept and the missing Claude or Codex layers will be added.` | `What's already set up will be kept, and I'll add the parts that are missing.` |
| `A recognized earlier manifest will be moved into the supported location and combined with the missing layers.` | `I recognize an earlier setup. I'll bring it forward and add what's missing, keeping a copy first.` |
| `The existing manifest already describes the complete setup and will be kept.` | `Everything is already described correctly, so I'll keep it as it is.` |

## Accessibility

Tab order, question screen: sidebar, then each question row checkbox in display order, then **Not now**, then **Include what I have**. Review rows are focusable as static text so a screen reader reaches them, and carry no control. Entering the screen moves focus to the title, which is announced with its heading trait, so the question is heard before the choices.

Tab order, Your projects step: sidebar, **Choose folder…** or **Add another folder…**, each **Stop watching**, **Select all**, **Select none**, each project checkbox in display order, the already-set-up disclosure, **Back**, **I don't keep projects on this Mac**, **Skip for now**, **Continue**.

Tab order, popover drill-in: **‹ Back**, **Add all**, each row control in display order, the disclosure, **Add another folder…**, **Stop watching this folder**. Escape performs **‹ Back**, matching the existing **What changed** drill-in.

Every row is one combined accessible element: name, then state word, then caption, so a screen reader hears **Your Claude Copilot space, will be included, your own content is already in here** rather than three fragments. Cleared rows announce **will be left alone** plus the decline sentence, so the cost is heard, not only seen.

No state is carried by colour alone. Included rows carry a checkmark, review rows a raised hand, projects kept as is a raised hand plus the label **Kept as is**, failures a triangle plus **Couldn't add it right now**, and automatic setups a distinct caption. The glyph vocabulary is the one already in Detect's inventory.

Progress that changes without the person acting is announced once, not continuously: **Adding…** and its completion post a single accessibility announcement per row, and the step-level phase label keeps the existing frequently-updating header treatment.

Captions that carry meaning use the secondary label colour, never tertiary, so every sentence a decision depends on clears 4.5:1. Tertiary stays for the genuinely decorative.

The primary action is the default keyboard action on every screen here, and the disabled primary always carries its hint as help text, so a keyboard-only person is never left guessing why it will not fire.

Every destructive-sounding word in this spec is attached to a reversible action. **Stop watching**, **Not on this Mac**, and **Undo** are all reversible from the surface that offered them, so none of them requires a confirmation dialog, and none of them is announced as a warning.

## Architecture decision

Render the question with the mechanism Holding already uses: an inline phase over its origin stage, adding no sidebar row and changing no step number, built from the existing `StepShell` and `sectionCard`. A dedicated roadmap stage was the obvious alternative, and it fails on Consistency and standards, because a stage that exists only sometimes makes **Step N of M** lie. Folding the question into Detect's inventory card was the other, and it fails on Visibility of system status and Recognition rather than recall, because the one row that needs an answer would sit among six that do not. Reuse of the Holding mechanism scores best on Error prevention and on User control and freedom: the question arrives before any write, and Holding gains a route back to it, so refusal is no longer terminal.

Make the folder grant a real step, position seven of ten, immediately before Set up. Leaving it on Done, unconditionally, was cheaper and scores worse on Match between system and the real world: Done is a farewell, not a place to make a new decision, and a person who closes the window never sees it. Putting it before Departments scores worse on Flexibility and efficiency of use, because it interrupts the organization narrative with a personal one. Immediately before Set up keeps every write in Set up, keeps the existing steps in their existing order, and lets the same step both grant and choose.

Render the projects offer as a Region 6 notice evaluated independently of the single Region 6 prompt, and keep Region 5's closed action set closed. Adding a fifth action-row button scores worse on Hick's law and on Aesthetic and minimalist design in a 360 point column. Re-ordering the existing `else if` chain scores worse on Visibility of system status, because it only changes which state wins and still hides one behind another. Sequential rendering fixes the class of bug rather than one instance of it.

Do not notify for automatic project setup. Silence is the product's success state, and a system notification for a reversible act the person already granted is noise that trains dismissal. Discovery is carried by a one-time notice, a past-tense line in **What changed**, and a per-project caption with **Undo**, which together score better on Visibility of system status over the person's whole lifetime with the product than one interruption on day one.

Keep the app a renderer throughout. Every sentence above is either a fixed app string listed here or a CLI `detail` the app prints verbatim, every state word comes from a CLI enum, and every decision the app makes is the person's own selection sent straight back for the CLI to re-plan. The app gains no notion of what a marker is, no notion of which project is new, and no notion of what declining costs.

Rejected:

- A confirmation dialog before including existing content: the design already prevents the error it would guard against, because inclusion only ever adds and never replaces, so a dialog would only add ceremony to a safe act.
- All-or-nothing inclusion: several components can be in this state independently, and a single choice would force a person to decline something safe in order to decline something they are unsure about.
- Writing the marker at the moment the question is answered: it would put a write outside Set up, where every other write lives, and would make **Not now** irreversible in the other direction.
- Letting the app decide that a declined component can be dropped from setup: that is computing ecosystem state, and it belongs in the CLI's re-plan.
- A separate Projects window: it duplicates the popover's job, costs a window to manage, and strands the list away from the status it belongs to.
- A Settings-only home for the projects list: Settings is not built, and behaviour 2 requires the list to be reachable today.
- A badge on the menu bar icon for projects awaiting setup: a project that can have copilots is an offer, not a fault, and badging it would make the calm icon lie.
- Per-row **Add** buttons in the wizard step: the copilots those adds copy from do not exist on this Mac yet at step seven, so each button would have to fail or lie.
- Checkboxes plus a single **Add selected** in the popover drill-in: a returning person adding one project should not have to select and then confirm.
- Asking before automatic setup of a brand new project: there is nothing of theirs to protect and no judgement only they can make, so the question would be pure friction, and the answer would always be yes.
- Automatic setup for projects that existed when the folder was granted: something of theirs is already there, which is exactly the case that must be asked about.
- A time-boxed undo window: an undo that expires is an undo the person cannot rely on. Undo stays available for as long as the CLI can prove that what it added is still exactly what it added.
- Offering to remove the person's own files as part of undo: never-destroy, and no control in this spec will ever offer it.
