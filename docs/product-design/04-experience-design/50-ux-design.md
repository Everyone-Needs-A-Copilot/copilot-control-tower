# UX Design

<!--
FACILITATION GUIDE — UX Designer
=================================
The UX Designer takes the journey map and struggling moments from
the Service Designer and turns them into interaction patterns,
information architecture, and task flows.

PREREQUISITE: Journey maps, JTBD, moments that matter, and user
stories should be completed first.

CONVERSATION FLOW:
1. Define information architecture (what content exists, how it's organized)
2. Design task flows (step-by-step for key actions)
3. Establish interaction patterns (how users interact with elements)
4. Consider responsive strategy
5. Define accessibility requirements

QUESTIONS TO ASK:

## Round 1: Information Architecture
- "What are the main 'spaces' or areas in this product?"
- "If this product were a building, what rooms would it have?"
- "How should content be organized?"
- "What's the primary navigation model?"
- "What does the user need to see first? What can wait?"

## Round 2: Task Flows
For each core workflow:
- "Walk me through exactly what a user does to accomplish [task]."
- "What decisions do they make along the way?"
- "What information do they need at each step?"
- "Where could they go wrong? How do we recover?"
- "What's the shortest path to success?"

## Round 3: Interaction Patterns
- "How should the user interact with the core content?"
- "Are there moments of input vs. moments of consumption?"
- "What feedback should the user get when they take an action?"
- "Are there any interactions that should feel particularly delightful?"
- "What existing products have interactions that feel right for this?"

## Round 4: Responsive Strategy
- "What's the primary device? Desktop, tablet, mobile?"
- "Does the experience need to work differently on different devices?"
- "Are there features that only make sense on certain devices?"

## Round 5: Accessibility
- "Who might have difficulty using this product?"
- "What WCAG level are we targeting? (A, AA, AAA)"
- "Are there specific accessibility concerns given the nature of this product?"

SYNTHESIS:
Create task flows as numbered steps, not diagrams.
Information architecture as a simple hierarchy.
Keep everything grounded in the journey map — every design
decision should trace back to a user need or struggling moment.
-->

> **Status: rebuilt from evidence on 2026-08-02. Describes the shipping product at v0.3.2** (notarized arm64 disk image, built 2026-08-01 from commit `e0bf0c3`, embedding the pinned helper `cc 2.1.2`).
>
> **This is a retrofit, not a proposal.** The app is built and running in production inside one organization. Every claim below was read out of the shipping Swift in `native/` and describes what a person actually sees. Where the code and an older design document disagree, the code wins and the difference is named. Where something is genuinely unknown or unverified it is marked `<!-- TODO -->` rather than asserted, because the whole reason for this rebuild is that the previous documents claimed things that were not true.
>
> **What this product is, in one line for a non-technical reader:** a small icon in your menu bar that puts a technical person's superpowers into your hands, sets your AI copilots up on your Mac without you having to learn how, and then keeps them current quietly. The entire experience is designed around that promise. A person is never asked to complete a step that names a rank, a manifest, a package, a tier, a schema or a repository.

---

## Design Principles

<!-- Override generic UX conventions. Trace to journey map. -->

These are not aspirations. Each one is enforced somewhere in the shipping code, and each one deliberately overrides a convention that product design usually treats as a virtue.

| # | Principle | The convention it overrides | Where it is enforced in the shipped app |
|---|---|---|---|
| **P1** | **Silence is the success state.** When everything is fine, the menu-bar icon carries no mark at all and the app says nothing. There is no green celebration, no toast, no "All good!" | "Confirm success. Reward the user. Keep them engaged." | The `none` badge returns nothing to draw, so nothing is drawn (`native/models.swift`). A healthy verdict maps to `none` (`native/render-state.swift`). The popover header's glyph view draws nothing for `none`, with the in-code note "silence is the success state." |
| **P2** | **The icon cannot lie.** Every glyph, sentence and dot is a render of a verdict the helper already computed. There is no code path that can invent "healthy." | "Degrade gracefully. Estimate the state when you can't reach the backend." | `RenderState.from()` maps helper fields only; `RenderState.unreadable()` is the only other constructor and always produces the red mark plus "I can't read the setup right now, so I won't guess." The schema gate refuses to trust any field before the version matches (`native/cli-client.swift`). |
| **P3** | **Route by who owns the fix, never by what went wrong.** The seven Holding screens are chosen by whether the person, their organization, or nobody can act. Two failures with identical technical causes land on different screens when different people own them. | "Group errors by error type, so they're easy to catalogue." | `HoldingVariant` (`native/wizard.swift`) is documented as "chosen by WHO OWNS THE FIX, never by what went wrong": H1 whoever installs software, H2 and H3 nobody (retry), H4 the person (a decision), H5 nobody (wait), H6 the organization, H7 the person (a real fix). |
| **P4** | **Say what was left alone, every time.** Preservation is stated in the interface before the action, not buried in a log afterwards. | "Show what will change. Silence about the rest implies safety." | The three-row panel "Will add / Will preserve / Will not change" precedes every project write. Failure copy is "Nothing was changed." / "Nothing in it was changed." / "Nothing was undone." |
| **P5** | **No internal vocabulary ever reaches a person.** Not one screen asks someone to understand a rank, a manifest, a package, a tier, a schema version, a stage id or a repository slug. | "Use the domain's real terms. Users will learn them." | The six engine stages are renamed in plain words for the Set up checklist ("Giving this Mac its own key"), with the rule stated in-code: "no stage ids, internal state names, or jargon in a user-facing string." The same is done for copilot names and layer names in `native/render-state.swift`. |
| **P6** | **No time estimate, no countdown, no percentage.** Progress is named outcomes, never elapsed time. | "Show a progress bar so the wait feels shorter." | The Set up count line reads "N of M outcomes reported", and its own documentation says the numerator "counts terminal reports, not elapsed time and not only successes." The sign-in poll interval is held as bookkeeping and never rendered. Timer-paced fake progress was deliberately removed. |
| **P7** | **Shape first, colour second, words always.** Every status has a distinct symbol and a sentence. Colour never carries a state on its own. | "Use a colour-coded severity scale. It's faster to scan." | All twelve badge tokens map to a distinct symbol before a colour. The six Set up row states have six distinct symbols and six distinct sentences. Every status row exposes an accessibility label containing the status in words. |
| **P8** | **Never-started and in-flight must never look the same.** A row that has not begun cannot animate. | "Just show a spinner until it's done." | `SetupRowState.notStarted` and `.working` are separate cases and the row renderer has no branch from not-started to a spinner. Every spinner in the user surfaces goes through one construction site that *requires* the name of the thing being waited on. |
| **P9** | **An offer is not a fault.** Work a person could do, but does not have to, never raises an alarm. | "Surface every actionable item as a notification badge." | The projects notice carries no menu-bar badge and reads "N projects can have your copilots. Nothing is added until you say so." A department you are entitled to but have not joined renders as a quiet "AVAILABLE TO JOIN" row, never as a warning. |
| **P10** | **Leaving is always allowed and always safe.** Every long flow can be abandoned mid-way and picked up later from the menu bar. | "Complete the wizard or lose your progress." | "Continue in the menu bar" appears on the Holding screens. Settings' "Finish Copilot Setup" and "Open project aftercare…" re-enter the same setup window at the right place. The projects step carries a standing card headed "Come back whenever you want." |
| **P11** | **At most one prompt, any number of notices.** The interface interrupts for a decision only once at a time; information may stack. | "Show the user everything that needs their attention." | The popover's prompt lane checks the unsaved-changes hold first, then the permission prompt, and never renders both. Notices render sequentially and independently, which the code records as a deliberate fix so that "the unsaved-changes prompt can no longer make a notice invisible." |
| **P12** | **Democratization is the test.** If a step needs technical judgement the person does not have, the step is wrong, not the person. | "Expose the power. Let advanced users go deeper." | The setup flow asks a person for exactly three things: their GitHub sign-in, sometimes their organization's name, and where they keep their projects. Everything else it either does, or explains and routes to whoever actually owns it. |

**When these conflict:** P2 (cannot lie) outranks P3 (route by owner), which outranks P1 (silence). One more honest state always beats a smaller interface, because a false "everything's fine" is the worst outcome this product can produce.

---

## Information Architecture

<!-- From Round 1: The structure of the product -->

**In one sentence:** one always-present menu-bar glyph opens three things (a status popover for every day, a nine-step setup window for the first run and for unfinished work, and a Settings window for the returning person), alongside a separately built Admin application whose sixteen-surface sidebar the ordinary build cannot reach at all.

### The surfaces that actually ship

| Surface | Container | How it opens | What it is for |
|---|---|---|---|
| **Menu-bar glyph** | A status item carrying the aviators mark, template-tinted, with an optional 9pt badge composited bottom-trailing | Always present; the app has no Dock icon | The one honest state of the whole machine, at a glance |
| **Popover** | A transient popover, fixed 360pt wide | Left-click the glyph | The day-to-day home: status, your copilots, joinable departments, connections, actions, and the one prompt lane |
| **Right-click menu** | A four-item menu (five in the Admin build) | Right-click or Ctrl-click the glyph | Keyboard and habit shortcut to the same actions |
| **Setup window** | A titled window, 960x720 ideal, split into a roadmap sidebar and a step pane | Automatically on first launch; the "Set up" action; four named re-entry routes | The nine-step first run, and where unfinished work is finished |
| **Settings window** | A titled window, 820x760 ideal, one scrolling column of cards | "Settings…" in the popover, "Settings..." in the menu, or `⌘,` | The returning person's read-only home: what is set up, what is connected, what your projects look like |
| **Admin application** | A separate binary with its own Dock presence and a two-section sidebar | Only exists in the Admin build | Standing an organization's shared setup up, and governing it afterwards |

Two facts about this map matter more than the rest. First, **the ordinary build is structurally unable to reach Admin**: the "Open Administration..." item lives inside a compile-time guard, and the user build's source list deliberately excludes the Admin files. Hiding is not sufficient when the exposure itself is the harm. Second, **there is exactly one install path**. There is no silent variant, no managed lane, no enterprise mode, no zero-touch install. Every person in every organization walks the same nine steps.

### Inside the popover: six regions, always in this order

The popover is a vertical stack. A region appears only when it carries information, so a machine where everything is fine shows very little.

```
┌──────────────────────────────────────────────┐
│ 1  STATUS HEADER                             │  the one honest sentence and its mark
│      [mark]  Everything is set up.           │
│              this-mac.local                  │
├──────────────────────────────────────────────┤
│ 2  YOUR COPILOTS                             │  one row per copilot, four layer cells each
│      Knowledge Copilot          [dot]        │
│      CLI Copilot                [dot]        │
│      Claude Copilot             [dot]        │
│      Codex Copilot              [dot]        │
├──────────────────────────────────────────────┤
│ 3  AVAILABLE TO JOIN        (only if any)    │  entitled, not yet joined
│      Sales                      [Join]       │
├──────────────────────────────────────────────┤
│ 4  SHARED WITH YOUR TEAM                     │  read-only, nothing to sign into
│    YOUR ACCOUNTS                             │
│      GitHub                  Signed in       │
├──────────────────────────────────────────────┤
│ 5  ACTION ROW                                │
│      [Sync now]  What changed   Settings…    │  "Set up" also appears when needed
├──────────────────────────────────────────────┤
│ 6  ONE PROMPT, THEN ANY NUMBER OF NOTICES    │
└──────────────────────────────────────────────┘
```

- **Region 1** renders the helper's sentence verbatim, with the machine's name below it in a quieter voice. It swaps to "Bringing everything up to date…" while a manual sync is in flight, and the mark swaps to the syncing shape at the same moment.
- **Region 2** is one row per copilot, each expanding to its foundation, organization, department and personal cells. A row's own mark is the worst of its cells. This is the corrected core of the product: your copilots across the layers you belong to, never a catalogue of the things you build with them.
- **Region 3** appears only when the helper reports a layer you are entitled to and have not joined. It is an offer, so it never badges the menu bar.
- **Region 4** keeps two registers permanently separated: things that are simply ready for you because of who you are ("Ready for you. Nothing to sign into.") and accounts you signed into yourself. Merging those two was the most consequential domain error in an earlier design pass, and the separation is now structural rather than visual.
- **Region 5** never contains an "Update" button, because updates install themselves. "Sync now" disables itself while offline or already syncing and prints "Waiting for the network." underneath when offline. "What changed" appears only when there is something to show. "Set up" appears only when the helper says setup is incomplete.
- **Region 6** carries at most one prompt, then any number of notices. Two drill-ins live here without opening a window ("What changed" and "Your projects"), both using the same back-and-drill-in grammar.

### Inside the right-click menu

Exactly: **Sync now** (disabled while syncing or offline), **What changed**, **Settings...** (`⌘,`), a separator, **Quit** (`⌘q`). The Admin build inserts **Open Administration...** with its own separator before Quit.

<!-- TODO: docs/03-design/control-tower-interaction-spec.md §1.6 specifies "About Copilot Control Tower" and "Preferences..." in this menu. The shipped menu has neither. Confirm with the owner whether the shipped set is the intended one (it is more useful and shorter than the spec's) so the spec row can be retired, or whether About should be added. -->

### Inside Settings: a header and three cards

Settings is deliberately read-only. Opening it never applies anything; every change routes back out to the flow that owns it.

1. **"Your setup"** header. It reads either "Your ecosystem is ready" or "Your Copilot setup is incomplete", followed by a count of the layers already in place, and when incomplete, a **Finish Copilot Setup** button that reopens the setup window after a fresh check.
2. **"Your copilots"** card. Four expandable rows, one per copilot: Knowledge, CLI, Claude, Codex. Each expands to its Foundation, Organization, Department and Personal rows, each carrying a state word, a mark, and the helper's own plain explanation. Above them sits the visible folder where the repositories live, plus the reassurance "Personal is yours; its repository is private, but its checkout stays visible in your Copilot repository folder."
3. **"Your connections"** card. The GitHub row first, then the organization's declared roster grouped by whether it is ready, needs a credential, or could not be checked.
4. **"Your projects"** card. A one-line summary sentence, one navigable row per non-empty project category with its count, the standing "Come back whenever you want" card, and an **Open project aftercare…** button.

The four-by-four grid inside card 2 is the load-bearing idea of the whole screen: **four copilots, four layers each, sixteen pieces of evidence, none of them ever fabricated.** A layer with no evidence says "Not connected", "Not joined" or "Could not check". None of those is ever rendered as ready.

### Inside Admin: two sections, sixteen surfaces

- **Onboarding** (eleven, do-once): Orientation, Prerequisites, Contacts, Connect GitHub, Describe your organization, Integrations, Secret store, Review setup, Organization setup, Setup check, Done.
- **Governance** (five, occasional): Add a department, Someone left, Connect the shared store, Org setup, Analytics.

Admin computes nothing about the organization either. A deterministic engine makes every existence and idempotency decision, always checking before acting, and Admin renders the result. Surfaces with no real seam yet render their honest degraded state and are marked as such in the code, rather than filled with plausible fake data.

### What is deliberately not a surface

No catalogue of the things you build with your copilots. No chat box. No "mark this healthy anyway" override. No fleet or device dashboard. No mobile-device-management screen of any kind. No in-app updater interface, because a new version is a new signed disk image and every release note names the previous one to roll back to. No control anywhere that lets a local setting weaken a security posture that was inherited.

---

## Task Flows

<!-- From Round 2: Step-by-step for each core workflow -->

### Flow 1: The first run, stage by stage

The setup window opens by itself the first time the app launches. It is a split view: a roadmap sidebar on the left listing all nine stages with done, current and upcoming marks, and the current step on the right with an eyebrow, a title, an introduction, content, and a footer holding a leading Back and a trailing primary action. Completed rows in the sidebar are clickable to review; upcoming rows are not.

**Stage 1 of 9, Welcome.** Title: "Welcome to your copilots." It states plainly that "You don't need to be technical for any of this", lists the three copilots everyone gets with one benefit sentence each, and lists the two things to have handy (a GitHub account, and the GitHub command line, which the app sets up if it is missing). A short welcome video is linked. Leading action is **Quit**; the primary is **Get Started**.

**Stage 2 of 9, Connect GitHub.** A sign-in that happens in the browser, on GitHub's own page, with the reassurance "Control Tower never asks for your password." The screen shows a code with **Copy code**, an **Open GitHub** button, the line "Waiting for you to finish in your browser…" and, because a lost browser window is the common failure, a second route back: "Didn't see the browser? **Open it again**". No credential can exist on this screen by construction: the state carries only the code, the address, the poll handle and the interval. On success the card collapses to a green check and "Signed in as *you*." **Continue** stays disabled until then.

**Stage 2.1, "Which organization are you with?"** Not a numbered step and it takes no sidebar row. It appears inline over Connect GitHub, and only when the helper says an organization is required and this Mac's own admin record cannot answer silently. One field. Pasting a full GitHub address rewrites it in place to the bare name with no message, because the rewrite is its own feedback. Three closed validations fire only after the field has been touched and is non-empty: a name with spaces offers a one-click **Use Acme-Co** correction, an email address is named as an email address, and anything else GitHub would reject gets a plain rule. The disabled primary always shows its reason as visible text, not only as a tooltip. Leading actions are **Help me find it** and **Continue in the menu bar**.

**Stage 3 of 9, Detect.** Title: "Checking what's already here", with the promise that Control Tower "keeps the parts that are already right, safely moves or repairs recognized earlier setup, and leaves anything unfamiliar untouched." While it runs, a shared progress card and a roster being checked. When it lands, it shows the visible folder where copilot repositories will live (with **Choose folder…**), a one-line summary of how many expected layers exist and how many need an action, and one expandable row per copilot listing every layer with its role, its repository, its action and the helper's own explanation. The primary is **Review setup**, disabled until the check finishes and a folder is chosen.

**Stage 3.1, "One question first."** Also inline, also without a sidebar row, and only when the plan found something that is already the person's. Title: "Want me to include what you already have?" Cards separate what is already in your GitHub account from what is already on this Mac, one checkbox per item, and a single app-authored guarantee underneath: "Nothing you already have is changed. Setup only adds what's missing." Leading is **Not now**; the primary is **Include what I have**, disabled with its reason visible until something is chosen.

**Stage 4 of 9, What you're getting.** Title: "Here's what you're getting". This step's design is the deliberate absence of a choice: "Everyone on your team gets all of this. There's nothing to pick." The three standard copilots are listed as confirmations, not options. One optional checkbox exists: "I also use Codex. Include Codex Copilot too." That is the only component decision in the entire flow, and it is framed as a personal preference rather than a configuration.

**Stage 5 of 9, Departments.** Title: "Departments you can join", with the reassurance that you can come back to this later from Settings or the menu bar. Only departments you are already entitled to ever appear, so no administrative decision leaks into this screen. Each row carries one of five states in words (Joined, Available to join, Joining…, Waiting for the network, or a plain not-available caption) and a **Join** button only on the joinable ones. If there are none: "No departments are available to you yet. When someone adds you to one, it'll show up here." Leading actions are **Back** and **Skip for now**.

**Stage 6 of 9, Your connections.** Two cards. "Ready to use" always begins with the GitHub connection just established, then any organization connection the helper can prove is ready. "Available to connect" lists connections whose credentials are missing and names exactly what is missing in plain language ("Needs 2 credentials in your organization's secret store: …"), and groups anything unverifiable under the helper's own honest explanation. A helper too old to answer at all degrades to the same empty state plus a quiet "Update to see your organization's connections." The intro sets the boundary explicitly: these are "the connections Control Tower can prove are ready for you."

**Stage 7 of 9, Your projects.** The title changes with what was found: "Where do you keep your projects?", then "N projects found", then a category name, then a single project's name as the person drills in. The person chooses a folder; the app checks only the folders they selected; each project is sorted into one of five helper-authored categories. Selection here is by checkbox rather than immediate action, because at this point in the flow the copilots a project would copy from do not exist on this Mac yet. The primary action names its own consequence: **Continue setup**, or **Set up 3 and continue**.

**Stage 8 of 9, Set up.** Title: "Setting up your copilots", with the intro "This part runs on its own. Keep this window open, or close it and let Control Tower finish in the menu bar." One line of honest progress ("4 of 9 outcomes reported."), one main row, a "What this includes" disclosure holding the six named stages, and one row per chosen project. Six row states, six shapes, six sentences, including the reconciliation state "Setup didn't say what happened here." for any row the run never mentioned. If projects stop the run, the screen retitles itself "Some projects need another look" and offers **Review projects**, **Try again** and **Continue without projects**.

**Stage 9 of 9, Verify.** While checking: "Making sure everything's current", with the intro "The only success here is everything actually being up to date." On success: "Your copilots are ready", with a "Ready now" card listing the GitHub connection and each copilot's verified state, a "Still to do" card only when something genuinely remains, a projects card whose wording differs for set up, partly set up, skipped or declined, and a "What happens next" card explaining the menu bar: "Look for the aviators: a quiet icon means there is nothing you need to do." The primary is **Finish setup**. If the completion rule does not pass, this screen refuses to congratulate: it renders the honest-incomplete pattern instead, and the finish action is not reachable from it. There is no hedged middle wording.

**The Holding screens.** At any stage a failure routes to one of seven Holding screens, rendered inline over the stage it came from, never adding a sidebar row, never a dead end.

| Variant | Eyebrow | Title | Who owns the fix |
|---|---|---|---|
| H1 | ONE MORE PIECE TO INSTALL | "The setup helper isn't installed yet" | Whoever installs software on this Mac |
| H2 | SETUP PAUSED | "I can't read your setup, so I've paused" | Nobody: retry |
| H3 | SETUP PAUSED | "I couldn't finish one part of setup" | Nobody: retry |
| H4 | ONE THING TO DECIDE | "Something here is already yours" | The person, and it is a decision rather than a fix |
| H5 | WAITING FOR THE NETWORK | "I'll pick this up when you're back online" / "Something else is updating right now" | Nobody: wait |
| H6 | WAITING ON YOUR ORGANIZATION | "Your organization has a bit left to set up" | The organization, with the person as courier |
| H7 | ONE THING ONLY YOU CAN DO | "Setup needs one permission from you" | The person, and it is a real fix they can complete here |

### Flow 2: The everyday glance

1. The app checks every 300 seconds, and also on launch and every time the popover opens, so an open popover is never showing stale data.
2. Several reads run at once. The main verdict drives the glyph and the sentence. **Any secondary read that fails degrades quietly and never blocks the verdict**, and never claims a pending offer it could not confirm.
3. If everything is fine, the glyph carries no mark and the person does nothing at all. That is the whole flow, and it is the intended one.

### Flow 3: Sync now

1. Click **Sync now** in the popover or the menu. It is inert while offline or already syncing.
2. The header swaps immediately to "Bringing everything up to date…" with the syncing mark. There is no percentage and no estimate.
3. The app applies pending changes, rolls the result up across projects, then re-reads the verdict.
4. **What changed** appears when there is something to show, opening a "Recently" drill-in with per-copilot lines such as "Updated Claude Copilot across 12 of your projects, to v5.9.0." and a "See projects ›" link. When there is nothing: "Nothing has changed since you last looked."

### Flow 4: Join a department from the menu bar

1. The helper reports a layer you are entitled to and have not joined. An "AVAILABLE TO JOIN" row appears. No badge, no alarm.
2. Click **Join**. The row shows a named waiting indicator and the button is gone while it runs.
3. On success the row simply disappears and a full refresh runs, so the copilot rows fill in with their new layer. **The tree filling in is the reward. There is no toast.**
4. Every other outcome gets its own sentence, and only the retryable ones get their button back: no longer available to you (no retry), waiting for the network (retry), or could not join right now (retry).
5. If nothing answers within 20 seconds, the row stops presenting itself as progress and reads "Sales hasn't come through yet. Nothing was changed." That is deliberately different wording from a reported failure, so a stall is never misread as an answer.

### Flow 5: Getting your copilots into a project

Three distinct routes, chosen by the helper, never by the app.

- **Automatic.** A brand-new project in a watched folder, where nothing of the person's is at risk and no decision is theirs to make, is set up silently on the check that already runs. The person perceives nothing at the moment it happens. The first time it ever happens they get one notice: "New projects get your copilots automatically now. I just set up *project*." That notice fires once, ever, and after it the fact still appears as a past-tense line in "What changed".
- **Can finish automatically.** The drill-in shows the three-row preservation panel, then a **Finish safely** button. Nothing is written until it is pressed.
- **Needs guided setup.** The helper writes a plan; the app shows what will be added, preserved and left alone, the full prompt behind a disclosure, and **Run in Codex** / **Run in Claude Code** / **Copy prompt**. Running one opens a real, visible terminal session, and a **Bring Terminal forward** control appears while it is out there. When the person returns, the app verifies both assistants itself: "Re-inspects both Claude and Codex; it does not trust the external assistant's report."

Two further categories exist and are honest about their limits. **Needs the project owner** offers a prepared handoff to copy or share and changes nothing: "Control Tower will not change this project without that decision." **Couldn't confirm** shows exactly what could not be proven, offers a read-only diagnostic session, a copyable report and **Check again**.

Undo is offered on an automatically set up project for exactly as long as the helper can still prove that what it added is untouched. When it cannot, **there is no control at all, never a disabled one with no explanation**, and the row's own caption carries the reason.

### Flow 6: Returning to unfinished work

1. Open Settings from the popover or `⌘,`.
2. The header says whether the setup is complete and offers **Finish Copilot Setup**, which reopens the same setup window after a fresh check. It does not replay Welcome and it does not reset anything.
3. The projects card offers **Open project aftercare…** and one row per category, each of which reopens the setup window directly on that category.
4. Everything in Settings is a read. Nothing is created, downloaded or changed by opening the window.

### Flow 7: Granting a permission only you can give

1. The regular check notices the helper reporting that this Mac's key was not permitted. A prompt appears in the popover: "GitHub needs one more permission before this Mac can finish setting up."
2. **Grant this on GitHub** reopens the setup window directly onto the H7 screen. It does not reimplement the flow, so it inherits H7's own honest degradation for free.
3. H7 runs a second, narrower browser grant with explicit terminal states for a mismatched identity and for an insufficient grant. If the mechanism is unavailable on this helper, the screen falls back to a manual sheet rather than dead-ending.

There is a sibling of this flow that is deliberately a notice rather than a prompt, because it is an offer the person can shrug off: "This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.", with **Add the connection**.

---

## Interaction Patterns

<!-- From Round 3: How users interact with elements -->

### The named-wait rule

**Every spinner in the user-facing surfaces must know the name of what it is waiting on.** One construction site enforces it: the indicator type takes a required subject and uses it as its accessibility label. A row that has not started has no branch that reaches it. This closes a whole class of "something is happening, unclear what" states by construction rather than by review.

### The silence path

Any named wait that goes 20 seconds without an answer stops presenting itself as progress and states plainly that nothing came through and nothing was changed, with the retry control restored. Each attempt carries a generation number, so a slow answer from an abandoned attempt can never overwrite a newer one.

### Drill-in, never a new window

The popover has two drill-ins and both use the same grammar: a `‹ Back` or `‹ All projects` control at the top left, then a title, then content. Neither opens a window, a modal or a sheet. Sheets are used in exactly five places in the setup window, all of them genuinely blocking sub-tasks: installing the helper, granting a permission, the manual fallback for that grant, the organization sign-in identifier, and the "help me find my organization's name" explainer.

### Progressive disclosure

Detail is available and never front-loaded. Copilot rows are collapsed disclosures. The Set up checklist hides its six named stages behind "What this includes". A guided plan hides its full prompt behind "Show full prompt". A project that could not be confirmed hides its raw evidence behind "Setup Control Tower recognized". Every Holding screen with support detail hides it behind a disclosure and prints only lines it genuinely has, on the stated rule "Never print unknown. A missing line is honest."

### Microinteractions, defined

| Interaction | Trigger | Rules | Feedback | What repeats or changes |
|---|---|---|---|---|
| **Join a department** | Click **Join** on an available row | One attempt per row, generation-guarded; blocked while offline or syncing, with the reason shown | Named waiting indicator replaces the button; success clears the row and refreshes the tree; each failure gets its own sentence | Retry appears only for retryable outcomes; a stall after 20s gets different wording than a failure |
| **Sync now** | Click in the popover or the menu | Guarded against re-entry and against running while offline | The header sentence and mark swap immediately to the syncing pair; "What changed" appears afterwards if there is anything | The disabled state plus the "Waiting for the network." line is the offline feedback |
| **A Set up checklist row** | The engine reports a real outcome | Six exclusive states; never set by a timer | A distinct symbol, a distinct sentence, and a named spinner only while working | The count line uses a fixed real denominator that never moves mid-run |
| **The sign-in code** | Entering Connect GitHub | The code is selectable and copyable; no credential exists on the surface | "Waiting for you to finish in your browser…" plus a second way back to the browser | On success the card collapses to one green line naming who signed in |
| **Automatic project setup** | The regular check finds a new project with nothing of yours at risk | Applies exactly what the helper said, then re-reads rather than assembling the result locally | Nothing at the moment it happens; one lifetime notice afterwards; a past-tense line in "What changed" every time | The lifetime notice is gated so it can fire only once, ever |
| **Undo a project** | Click Undo while the helper can still prove nothing was touched | The same generation guard as Join | Named waiting indicator, then the row returns to offering setup | When undo is no longer provable the control is absent and the caption explains why |

### Loading

| Where | What is shown | Why |
|---|---|---|
| Popover, first paint and every refresh | The last honest state, updated in place | Avoids flicker on a surface that refreshes every 300s |
| Detect | A shared progress card plus a roster of copilots being checked | The list shape is known |
| Projects step, first load | A named checking line, a labelled indicator, and three placeholder blocks | The card shape is known |
| Set up | Named outcome rows, no bar and no estimate | Duration is genuinely unknown, and an estimate would be a lie |
| Connections | "Checking your organization's connections…" | Short and discrete |
| Settings | One labelled line per card, for example "Checking your projects…" | Several independent reads that resolve separately |
| Anywhere | Never a bare unlabelled spinner, never a blank pane, never an optimistic value | The app computes nothing, so it cannot optimistically show success |

### Empty states

| Where | What it says | What it offers |
|---|---|---|
| Everything fine | "Everything is set up." | Nothing. That is the point |
| No departments | "No departments are available to you yet. When someone adds you to one, it'll show up here." | Nothing. An honest wait |
| Nothing changed | "Nothing has changed since you last looked." | Nothing |
| No folder chosen | "Control Tower isn't watching any folder yet. Choose the folder where you keep your projects and it will set your copilots up there." | **Choose folder…** |
| Folder chosen, no projects | "No projects in that folder yet. Any new one you create will get your copilots automatically." | Nothing needed |
| Projects declined | "You chose not to use project setup on this Mac. You can return whenever you want." | **Set up projects…** |
| No further connections | "No additional organization connections are available in Control Tower right now." | Nothing, plus a quiet update hint when the helper is too old to answer |
| No prompt or notice | The region does not render | Silence is success |

An empty state is never an error, and the prompt lane's empty state is literally the absence of the region.

### Copy rules that are enforced, not merely recommended

No em-dashes in any user-facing string. No button labelled "Submit" anywhere; every primary names its consequence ("Get Started", "Review setup", "Set up 3 and continue", "Finish safely", "Finish setup", "Grant this on GitHub", "Add the connection"). No "Update" button, because updates install themselves. No raw error text, no configuration syntax, no serialization message, no version-control conflict marker. Every disabled primary carries its reason as visible text as well as help text.

---

## State and Status Vocabulary

*Not a template section. Added because this product's status language is the spine of its user experience.*

### The twelve badge tokens

One closed vocabulary is shared by the menu-bar glyph, the popover header, the copilot rows and the Holding screens' marks. Shape encodes the state; colour is only ever a second channel.

| Token | Symbol | Colour | What it means to a person | Where it is reachable today |
|---|---|---|---|---|
| `none` | nothing drawn | n/a | Everything is set up. Nothing for you to do | Menu bar, popover header, H4 |
| `pass` | filled circle | green | This particular layer or copilot checked out | Copilot and layer rows only, never the menu bar |
| `hollow` | outline circle | secondary | Setup is not finished yet. Not a fault | Menu bar, popover header, H1 |
| `ring` | circular arrows | label | Bringing things up to date right now | Menu bar, popover header |
| `key` | filled key | blue | You need to sign in, or to grant one permission | Menu bar, popover header, H7 |
| `triangle` | filled warning triangle | orange | Something genuinely needs attention | Menu bar, popover header, copilot rows, H3 |
| `wrench` | adjustable wrench | secondary | Waiting on setup from your organization | H6 |
| `clock` | clock | secondary | Waiting: either offline, or something else is running | H5 |
| `cloud-slash` | crossed-out cloud | secondary | Offline | Menu bar, popover header |
| `bang` | filled exclamation circle | red | The only red state: "I can't read the setup right now, so I won't guess" | Menu bar, popover header, H2 |
| `update` | download arrow in a circle | blue | An update is ready | **Defined but not currently reachable** |
| `spinner` | download-box symbol | secondary | The app itself is updating | **Defined but not currently reachable** |

**What the twelve communicate, together:** every meaningfully different thing that can be true about a person's setup, in a mark small enough to read at menu-bar size, legible in grayscale, legible frozen, with a sentence beside it saying the same thing in words. The vocabulary is closed on purpose. A new state cannot be improvised at a call site; it has to be added here. That is what keeps the menu bar honest.

<!-- TODO: `update` and `spinner` are defined in the vocabulary but no shipped code path selects them. native/render-state.swift deliberately collapses update-available and updating-app onto `ring`, and its own comment flags this as a frozen-plan decision to revisit ("Revisit against the fuller copy-deck table in a later phase if the owner wants the richer glyph set"). Two questions to settle: (a) does an available update deserve its own distinguishable mark, and (b) since the app has no in-app updater at all, is `spinner` now dead vocabulary that should be retired? -->

### The other closed vocabularies

The product uses several small, closed, exhaustive state sets rather than one large severity scale. Each is total over its own domain, which is what stops a screen from ever having an undefined state.

- **Ten helper statuses**, each with its own sentence: healthy, setup-needed, waiting on the organization, syncing, update available, needs attention, signed out, offline, waiting for the network, updating. The signed-out, waiting-on-organization and needs-attention sentences name the specific copilot and layer involved, so there is never a blended "something needs attention."
- **Six unreadable reasons** behind the single red state. The reason selects a plain sentence variant; **the reason token itself is never shown**, and the raw error text is never shown.
- **Seven Holding variants**, chosen by owner (see Flow 1).
- **Six Set up row states**: not started, working, done, deferred, could not finish, and never reported. Deferred is explicitly neither a success nor a failure: "the rest of setup may continue while the row remains explicit."
- **Five project categories**, all helper-authored: Ready ("No action needed"), Can finish automatically ("Review the exact additions first"), Needs guided setup ("A coding assistant can complete these"), Needs the project owner ("A named decision is required"), Couldn't confirm ("Review what could not be proven"). The app filters by these; it never assigns one.
- **Five Settings tier states**: Ready, Needs setup, Needs attention, Not joined, Could not check.
- **Three join row states**: idle, joining, and a terminal message that carries its own retryability.

<!-- TODO: Settings uses its own five-value status vocabulary with its own symbols, rather than the twelve-token badge set the tray and popover share. The two agree in spirit and never contradict each other, but they are two separately maintained sets. Worth a decision: unify them, or document the split as intentional on the grounds that Settings is a roomier surface than a menu bar and can carry a fuller vocabulary. -->

---

## Error, Failure and Recovery

*Not a template section. Added because failure handling is where this product's quality actually lives.*

### Two registers, and only two

1. **Honest holding.** Offline, waiting for the network, waiting on the organization, a blocked stage, a join that could not complete, a connection whose credential is missing. These are calm, named, attributed to whoever owns the fix, and always carry either a forward action or a plain statement that this will clear on its own. **They are first-class states, not errors.**
2. **Cannot read the setup.** The one red state. The app cannot trust the contract it is reading, so it renders no copilot rows, no join row, one sentence ("I can't read the setup right now, so I won't guess"), and a retry. A missing security field fails closed into this state rather than into anything that looks safe.

### Prevention before recovery

The shipped app prefers, in this order:

1. **Make the mistake impossible.** Sync is inert while offline. A second join attempt on the same row cannot start. The setup-transaction proof refuses to run unless it is pointed at an inert fixture, on the stated rule that "an arbitrary path must never turn a selftest into a live mutation."
2. **Guide toward the right input.** A pasted GitHub address is silently rewritten to the bare name. A name containing spaces offers a one-click corrected value. A disabled primary always says what would enable it.
3. **Make it reversible.** Undo is offered on automatic project setup for exactly as long as the helper can prove it is still safe, and a previous setup is preserved in a rollback copy that Verify names out loud.
4. **Ask only when the decision is genuinely the person's.** There is no confirmation dialogue guarding a routine action anywhere in the product. The two things that stop and ask are "Something here is already yours" and a project whose owner must decide.

### Rules that hold everywhere

- **Never destroy.** Failure copy states what survived, not only what failed.
- **An unrecognized value fails closed.** A connection state the app does not recognise is grouped with the unverifiable ones and gets an honest explanation. It is never shown as ready and never silently dropped.
- **A stall is not a failure.** Different wording, deliberately, so a slow network is never reported as a refusal.
- **A secondary failure never poisons the primary verdict.** If the department list, the account check, the freshness sweep or the project scan fails, the main status still renders and the affected region is simply absent.
- **A failed read never claims a pending offer.** The app would rather show nothing than assert something it could not confirm.
- **Recovery re-navigates rather than re-implements.** The menu-bar prompts reopen the screen that already knows how to handle the situation, so they inherit its honesty instead of duplicating it.
- **Verify cannot be talked into congratulating you.** If the completion rule does not pass, the finish action is unreachable and the honest-incomplete pattern renders instead.

---

## Responsive Strategy

<!-- From Round 4: Device priorities and adaptation -->

**One device: a Mac.** macOS only, Apple silicon, shipped as a signed and notarized disk image. There is no phone, tablet, web or Windows experience, and Windows is formally out of scope. The only responsive dimensions that exist here are window size, text size and system appearance.

| Surface | Sizing | Adaptation |
|---|---|---|
| Menu-bar glyph | 16pt tall, variable width, with a 9pt badge composited bottom-trailing | Template-tinted, so it follows light and dark menu bars automatically |
| Popover | Fixed 360pt wide, height fits its content | Regions appear and disappear, so height is the only variable. Text is set to wrap rather than truncate |
| Setup window | Minimum 820x620, ideal 960x720, resizable | Balanced split view; the roadmap sidebar is constrained to 240 to 280pt |
| Settings window | Minimum 760x650, ideal 820x760, resizable, position remembered between launches | One scrolling column of cards |
| Admin window | Sidebar plus detail, its own window, its own Dock presence | Two-section sidebar |

Long text is set to wrap vertically rather than clip in essentially every text view in the app, which is what lets larger system text sizes work without redesign. Materials use the system's own vibrancy, so Reduce Transparency falls back to opaque system colours automatically. Colours are system semantic colours throughout, so light mode, dark mode and Increase Contrast are inherited rather than reimplemented.

---

## Accessibility

<!-- From Round 5: WCAG targets and specific concerns -->

**Target: WCAG 2.1 AA, expressed through the macOS accessibility APIs.** This is a native application rather than a web page, so the conformance surface is VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast and Dynamic Type, not ARIA.

### What ships today

- **Roughly 163 explicit accessibility annotations across the shipping Swift**, concentrated exactly where status is communicated.
- **Status is always in words.** Every status row combines its children into a single element and announces "name, status, detail": "Sales, available to join"; "Claude Copilot, Ready"; "Personal, Needs setup, *the helper's own explanation*". No state anywhere depends on colour alone.
- **Decorative marks are hidden from assistive technology.** The popover header's status mark is explicitly hidden because the sentence next to it already carries the meaning. The same is true of every category icon, chevron and Holding badge.
- **The menu-bar item exposes the button role and the current status sentence as its label**, refreshed on every check.
- **The popover status sentence is marked as frequently updating**, so a change is announced without stealing focus.
- **Disabled primaries never hide their reason.** The reason renders as visible caption text *and* as help text, on the explicit rule that a hint you can only find by hovering is not a hint.
- **Focus moves to the title when a Holding screen appears**, through an explicit accessibility focus binding, so a keyboard or VoiceOver user is never stranded on a control that just disappeared. This is scoped to Holding on purpose and does not fan out into the ordinary steps.
- **The roadmap sidebar announces position and status**: "Step 5 of 9, Departments, current."
- **Reduce Motion is honoured on the setup window's step transition**, which becomes a short cross-fade instead of a slide.
- **The menu-bar badge does not animate at all.** No pulse, no rotation. This is stricter than the original specification, which called for a pulsing outline and a rotating ring, and it means every state is legible frozen, in grayscale, by design rather than by fallback.
- **Copyable values are selectable**: the sign-in code, the repository folder path, the full guided prompt, the verification command and the recognized-setup evidence. Secrets are never rendered, so they are never announced.
- **Keyboard.** The primary action on every step is the default action, so Return advances. `⌘,` opens Settings from the menu. `⌘q` quits. Every control is a standard system control, so Tab traversal, arrow-key list navigation and the system focus ring are inherited rather than reimplemented, and the focus ring is never restyled.

### Named gaps, stated honestly

<!-- TODO: The menu-bar item exposes an accessibility label (the status sentence) but no accessibility value naming the badge shape. The interaction spec §1.4 asks for a value such as "needs sign-in" or "a department is available to join". A VoiceOver user does hear the sentence, which carries the meaning in words, so this is a fidelity gap rather than a blocker. Confirm whether to add it. -->

<!-- TODO: Reduce Motion is read in exactly one place, the setup window's step transition. Nothing else in the app animates enough to need it today, but this must be re-checked if any motion is ever added. -->

<!-- TODO: No contrast measurement is recorded anywhere in the repository. The app uses system semantic colours throughout (green, orange, red, label, secondary label, tertiary label), which follow Apple's own contrast behaviour and respond to Increase Contrast, but there is no documented 4.5:1 audit of the actual rendered pairs, in particular small caption text over the translucent popover material. An audit is an open item. -->

<!-- TODO: Tab order is nowhere explicitly documented or pinned; it is the framework's default document order. That is very probably correct for these layouts, but "probably correct by default" is not the same as designed, and the popover in particular has a non-obvious reading order once Region 6 carries a prompt. Worth one keyboard-only pass to confirm, then record here. -->

<!-- TODO: The product contains exactly one accessibility hint ("Re-inspects both Claude and Codex; it does not trust the external assistant's report."). It is excellent, and it is the only one. Other consequential actions, notably Finish safely and Undo, could earn the same treatment. -->

### Who this product has to work for

The person this app is built for is, by design, **not technical**. That is the accessibility requirement that outranks every API detail: a screen that requires someone to know what a manifest is, or to interpret a raw error, has failed them just as completely as an unlabelled button fails a VoiceOver user. The two requirements point the same direction, which is why one set of rules serves both. Say the state in words. Name who owns the fix. Never hide the reason a control is unavailable. Never let colour be the only thing carrying meaning. Never claim something you cannot prove.
