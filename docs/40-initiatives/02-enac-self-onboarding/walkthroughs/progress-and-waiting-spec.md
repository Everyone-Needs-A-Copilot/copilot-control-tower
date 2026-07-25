# Progress and waiting

## Service outcome

Someone using Control Tower can always tell three things apart without asking anyone: work that has not started, work that is happening right now, and work that has stopped. Today they cannot, because a never-started operation and a live one draw the same spinner, and because the wizard's "Part 2 of 4" was paced by a timer rather than by anything real.

Progress is only ever a report on work that actually happened. When Control Tower knows how many things there are, it says so and names each one as it lands. When it does not know, it says what it is waiting for and refuses to imply a position. Nothing on screen is ever paced by a sleep, and no number on screen is ever a promise about the future.

A wait that goes wrong is the real test. A long step keeps the name of the thing it is working on visible, a step that stops answering says so in words and offers a way to find out the truth, and a run that ends never leaves a row looking like it is still coming. Completed work stays available as evidence, and a failure is never buried next to it.

No surface in this design shows a duration, a countdown, an estimate, or a percentage. It shows named things, and how many of them are done.

## Service blueprint

| Stage | Person sees and does | Control Tower does | Failure and recovery |
|---|---|---|---|
| Nothing has started | A still row or card: the words **Not started yet** (or **Not checked yet**) beside a hollow outline dot, plus the action that would start it. No animation anywhere. | Holds the run in a `notStarted` phase that has no animated rendering available to it at all. | If the automatic start never fired, the state is visible and actionable instead of masquerading as slow work. |
| Checking before changing | The heading of the work, plus **Checking your access and every space on GitHub first. Nothing has been changed yet.** Every row still reads **Not started yet**. | Runs the engine's read-only preflight; the work list is drawn but untouched. | A refusal during checking ends the run before any row moves, and the engine's own instruction is shown verbatim. |
| Work in flight | One named row is working, with an animated indicator and **Working on it now.** A count appears above the list once there are two or more rows: **4 of 16 done.** | Parses one line per step from the engine and attaches each to the row it names. Numerator only rises; denominator only grows. | A step naming something outside the plan appends a row and grows the denominator, with a plain note that setup handled something extra. |
| A long single step | The working row keeps its name and its place, and gains a second line: **Still working on this one. GitHub can be slow to answer.** The heading never changes. | Starts a silence watchdog when the row begins. Completed rows collapse, but never the working one. | If silence passes the watchdog, the row leaves the in-flight phase entirely rather than spinning on. |
| Work stops answering | A static warning glyph, **No answer yet.**, and a card explaining nothing was undone. Two actions: **Keep waiting** and **See what's really on GitHub**. | Moves the run to `stalled`, which has no animation. The truth path is the read-only setup check, not a guess. | Nothing is cancelled or rolled back; the engine is additive and safe to run again. |
| A step fails or is refused | The failing row stays expanded in place, in list order, with its own words and the engine's detail beneath. Successes collapse; failures never do. | Distinguishes **couldn't finish** from **stopped on purpose** and renders each differently. | Both offer running setup again; a refusal leads with reading GitHub first. |
| Work ends | The count disappears. Any row the run never mentioned reads **Setup didn't say what happened here.** | Reconciles every row against the run's exit, so no row can be left pending. | Ending with anything unfinished keeps the person on the run surface with a summary that names what is unfinished. |
| Evidence afterwards | On the next surface, **Show what setup did** reopens the finished list. | Keeps the reconciled list for the session. | Nothing is celebrated; the list is evidence, not a reward. |

## Interaction specification

### 1. The six waiting patterns, and when each applies

The choice is made by two questions, in this order: *do we know the list of things before work starts?* and *does the work report each thing as it lands?*

| Pattern | Use when | Renders as | Count |
|---|---|---|---|
| **P0. No affordance** | The work is local and finishes faster than a person can perceive. | The result. Nothing else. Escalates to P4 only if it has not returned within the settle delay. | None |
| **P1. Filling checklist** | The list is known before work starts **and** each item reports as it lands. | Every item as a row, filling in place, working row named. | **N of M done.** while alive only |
| **P2. Scoped wait** | The list is known before work starts, but the work reports nothing until it returns. | One animated indicator that names the scope, above the full list, every row **Not checked yet**, all resolving at once. | The scope is stated in the sentence, never as a fraction |
| **P3. Growing tally** | Items are discovered inside the work, so no denominator can exist. | A line that counts up and names what it has reached. No bar, no fraction, ever. | **6 checked so far.** |
| **P4. Named single wait** | One operation, one subject, no reportable interior, expected to be short. | A small indicator on that row or beside that button, with the subject named. | None |
| **P5. Human-paced wait** | The person is the bottleneck, not the machine. | A sentence about what *they* need to do, plus a way back in. No count, no timer. | None |

A plain spinner is legitimate in exactly P2, P4 and P5, and in every one of those it is attached to a named subject. A bare spinner with no named subject is never correct anywhere in this product. "We did not bother to find out" is not a pattern.

Applied to the current inventory:

| Today | Pattern | Why |
|---|---|---|
| Review: writing the setup file | **P0** | A local file write. A spinner for it implies distance that does not exist. |
| Review: what Admin found on GitHub | **P2**, upgrading to **P1** when the engine reports per target | The target list is the administrator's own plan; the engine returns one document at the end. |
| Setup check | **P2** | Same shape, read only. |
| Connect GitHub readiness | **P1** | Four named checks that already resolve one at a time. |
| Set up organization (the mutating run) | **P1**, with a bar as its summary | The engine already emits one line per step, and every line names a real thing. |
| Wizard: setting up your copilots | **P1** over one call plus one row per chosen project, each project resolving individually | The project loop is genuinely sequential and already countable. |
| Menu bar: joining a department | **P4** | One call, one named subject. |
| Menu bar: adding a project | **P4** | Same. |
| Checking other projects (fan-out) | **P3** | Projects are discovered inside the loop. A denominator would be invented. |
| GitHub sign-in in the browser | **P5** | Paced by a person and their browser. |

### 2. The rule that makes never-started unmistakable

The current defect is structural, not cosmetic: `WriteState` is a four-case enum whose `.idle` and `.working` share one `switch` branch, and readiness uses a plain `Bool`. A boolean cannot express "started but silent", so it can get stuck true forever and still look healthy.

Three constraints replace it, and together they make the confusion impossible rather than merely discouraged.

**Progress is a phase with timestamps, never a boolean.** `RunPhase` is `notStarted`, `alive(startedAt, lastLineAt, subject)`, `stalled(lastSubject)`, or `ended(Outcome)`. There is no `isWorking` anywhere in the model. Anything that wants to animate must first obtain an `alive` payload, and an `alive` payload always carries the name of what it is working on, so an unnamed animation cannot be constructed.

**The animated indicator is only reachable from `alive`.** One private view takes the `alive` payload as its initialiser argument and is the only place in the app that constructs a `ProgressView`. `notStarted` has no branch that can produce it, and the exhaustive `switch` over the phase forces every call site to write a distinct `notStarted` arm.

**A row's state is computed from the run, not stored on the row.** A row is only ever drawn as working when the run that owns it is `alive` and its own name is the current subject. When the run leaves `alive`, every row leaves working in the same instant, without any per-row bookkeeping that could drift.

The watchdog closes the loop: entering `alive` arms a silence timer, and silence past it moves the run to `stalled`, which has no animation. A dead operation therefore cannot look like a slow one, because after the watchdog nothing on screen is moving and the words have changed.

### 3. The six row states

Every row in every checklist uses this vocabulary. Text always carries the state; the glyph and colour only reinforce it.

| State | Glyph | Motion | Row text | Announced as |
|---|---|---|---|---|
| Not started | `circle`, tertiary | none, ever | `Not started yet.` (lists that read rather than change: `Not checked yet.`) | "not started yet" |
| Working | indeterminate indicator | native indeterminate | `Working on it now.` | "working on it now" |
| Working, silent a while | same indicator | unchanged | adds `Still working on this one. GitHub can be slow to answer.` | "still working on this one" |
| Done | `checkmark.circle.fill`, green | 150 ms cross-fade in | the engine's own detail, verbatim | "done" plus the detail |
| Couldn't finish | `xmark.circle.fill`, red | 150 ms cross-fade in | `Couldn't finish this one. Everything before it is still in place.` plus the engine's detail | "couldn't finish" plus the detail |
| Stopped on purpose | `hand.raised.circle.fill`, red | 150 ms cross-fade in | `Setup stopped here on purpose. Nothing after this was changed.` plus the engine's detail | "stopped on purpose" plus the detail |
| No answer | `exclamationmark.triangle.fill`, orange | motion **stops** | `No answer yet.` | "no answer yet" |
| Never reported | `questionmark.circle`, secondary | none | `Setup didn't say what happened here.` | "not reported" |

Six distinct shapes, six distinct sentences. Nothing in the set is distinguished by colour alone, and the two states a person is most likely to misread (not started, no answer) are the two with no motion at all.

**How a space is named.** A row is titled by what it is and who it is for: `Knowledge Copilot, for your whole organization`, `Claude Copilot, for Design`, `The Design team, so Design can reach its spaces`, `Your organization's setup file`, `Your organization's default access`. The GitHub name may appear beneath as small evidence text, and the engine's detail sentences are rendered verbatim even where they contain one. A GitHub name is never the label a person is asked to recognise.

### 4. P1 in detail: the mutating organization run

This is a second state of Review, not a new surface. While the run is alive, Back is removed, the primary is disabled with the hint `Setup is running. This finishes on its own.`, and the heading is fixed.

**The list, and where its number comes from.** One row per space in the plan the administrator just approved, one row per department team, one row for the organization's default access, one row for the setup file. For two harnesses and two departments that is twelve spaces, two teams, and two more, so sixteen rows, in the same order and with the same names the Review inventory card showed a moment earlier. The person is watching the list they just read.

**How the engine's lines land on rows.** Parsing only, with no model of the engine's ordering.

| Line the engine emits | Row it lands on |
|---|---|
| `readiness`, `brief`, `validate-slug`, `repository-plan` | the checking-first preamble, before any row moves |
| `org-base-permission` | the default-access row |
| the organization space steps | that space's row |
| the department space steps | that space's row |
| the layer package and branch protection steps | that same space's row |
| the department team step | that department's team row |
| the department access grant steps | that same team row |
| the setup file and leak scan steps | the setup file row |

A row goes done on the first line that names it and keeps the newest detail from any later line about it. A worse result always wins over a better one, so a space that was created and then failed protection reads as unfinished, never as done. This needs no knowledge of which step comes last, which is why it stays parsing rather than computing.

**Counting rules.** The numerator only rises. The denominator only grows: a line naming something not in the approved plan appends a row and adds one, with the note `Setup also handled 1 thing that wasn't in your plan. That's fine.` A fraction only exists while the run is alive; it is a description of work in flight, never a standing verdict, and it disappears the moment the run ends.

**Exact copy.**

- Heading, fixed for the whole run: `Setting up your organization`
- Intro during the preamble: `Checking your access and every space on GitHub first. Nothing has been changed yet.`
- Intro from the first change onward: `Setup only adds what's missing. Existing spaces are kept exactly as they are.`
- Count line, only with two or more rows: `4 of 16 done.`
- Roll-up of finished rows: `12 done.` with `Show what's done` and `Hide what's done`
- Extra-work note: `Setup also handled 1 thing that wasn't in your plan. That's fine.`
- Silence card, when the run stalls: `Setup hasn't reported anything for a while. Nothing has been undone, and nothing is lost.` Actions: `Keep waiting` and `See what's really on GitHub`
- End with everything done: the app advances to the existing completed surface, which gains `Show what setup did` so the list stays available as evidence. No celebration.
- End with something unfinished: `Setup stopped with 1 thing unfinished. Everything else is in place, and running setup again only picks up what's missing.` Actions: `Try setup again` and `See what's really on GitHub`
- End on a refusal: `Setup stopped on purpose before changing anything else.` followed by the engine's own instruction verbatim. Actions: `See what's really on GitHub` (primary) and `Try setup again`

**Long steps, and what stays on screen.** Finished rows collapse into the roll-up, except the most recently finished one, which stays visible in full so there is always evidence of forward motion. The working row is never collapsed, never scrolled away, and never renamed. The heading does not rotate labels: the old fake was a moving title with nothing underneath it, so in this design the title is the one thing that holds still and the list is the only thing that moves.

**Failures beside successes.** The list keeps plan order so things stay findable, and the roll-up only ever swallows successes. A failed or refused row stays expanded where it is, and the summary sentence names how many things are unfinished. No summary that mentions a failure may also read as success.

**The bar.** When the list is longer than seven rows, a determinate bar is drawn above it as the visual twin of the same count. It is never drawn without the count line and the named working row beside it, it carries no percentage text, it never appears for P2 through P5, and it disappears when the run ends. This is the only bar in the product.

### 5. P1 in detail: Connect GitHub readiness, and the wizard

**Readiness.** Four rows already exist with per-row status, so this is P1 today with no engine change. One correction is needed: all four rows currently flip to checking at once while only two calls are running, which shows two spinners for work that has not begun. Only the row whose check is actually running may be working; the rest stay `Not checked yet.` Copy: `2 of 4 checked.` while alive, then the existing per-row results. The existing `Not checked yet.` and the existing degraded lines are kept verbatim.

**The wizard's set-up step.** The `cyclePhases` sleep is deleted along with `Part N of M`. The replacement is a P1 list whose rows are one call plus one row per chosen project.

- Eyebrow unchanged: `Step 8 of 10`
- Heading, fixed: `Setting up your copilots`
- Intro unchanged: `This part runs on its own. Keep this window open, or close it and let Control Tower finish in the menu bar.`
- Row 1: `Your copilots on this Mac`, with a collapsed disclosure `What this includes` listing the six named stages in plain words (`Getting your organization's shared setup`, `Setting up your own copy on this Mac`, `Giving this Mac its own key`, `Writing down which copilots you get`, `Connecting your organization's shared store`, `Adding Codex Copilot`). Because those stages only arrive when the call returns, the disclosure is a P2 list inside a P1 row: every line reads `Not started yet.` until they all resolve together.
- One row per chosen project, titled with the project's own name. These resolve one at a time, because the loop really is sequential.
- Count line, only with two or more rows: `1 of 3 done.`
- Background note, because the wider project sweep is uncountable and never gates anything: `Also checking your other projects in the background. You don't have to wait for that.`
- A project that fails: `Couldn't set up Insights Copilot. Nothing in it was changed. You can add it later from the menu bar.`
- Summary when some projects failed: `2 of 3 projects are set up. 1 didn't work, and nothing in it was changed.`
- Failure of the main call keeps the existing holding state, unchanged.

### 6. P2 in detail: the two Review cards and the setup check

**Card: the file setup wrote for you** (P0, with P4 as its escape hatch). A local write gets no spinner. The states are still all present, because the never-started one is exactly the failure the audit found.

- Not started: `Not written yet.` beside a still outline dot, with `Write it now`
- Working, only past the settle delay: `Writing your setup file…`
- Done: existing copy kept verbatim, from `Setup wrote a plain description of your organization you can read:` through `It carries no secrets and no integrations.`
- Couldn't finish: existing copy kept verbatim, `I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again.` with `Try again`
- No answer: `Still writing your setup file. That's unusual for a file on this Mac.` with `Try again`

**Card: what Admin found on GitHub** (P2).

- Not started: `Not checked yet.` beside a still outline dot, with `Check GitHub now`
- Working: `Checking your 12 spaces on GitHub. Nothing is being changed.` with the indicator, above the full list of spaces, each row reading `Not checked yet.`
- Done: the existing per-space rows and the existing summary line, kept verbatim
- Couldn't finish: existing copy kept verbatim, with `Try again`
- No answer: `GitHub hasn't answered yet. Nothing has been changed.` with `Keep waiting` and `Try again`
- Nothing to check: `There's nothing to set up here. Check your organization name and departments.`

**The setup check** (P2, read only).

- Never run: existing copy kept verbatim, `Run the setup check before you hand this over. It catches blockers before your organization does.`
- Working: `Checking what's really on GitHub. This only reads, it changes nothing.`
- No answer: `GitHub hasn't answered yet. Nothing was changed by checking.` with `Try again`
- Results and the existing count-never-score summary line are unchanged.

### 7. P3, P4 and P5

**P3, the project sweep.** Menu bar only, never in a gating flow. Working: `Checking your other projects. 6 checked so far.` Ended: `Checked 9 projects. 2 were updated.` No bar, no fraction, no denominator, at any point.

**P4, single named operations.** Joining keeps `Joining Design…` with its quiet indicator, and gains a silence path: `Design hasn't come through yet. Nothing was changed.` with `Try again`. Adding a project keeps `Adding…` visually, since the row already carries the project's name, and gains the same silence path: `Insights Copilot hasn't come through yet. Nothing in it was changed.` with `Try again`. The idle row keeps its button and never shows an indicator.

**P5, waiting on a person.** The wait names what *they* must do, not what the app is doing. The existing lines are kept verbatim: `Waiting for you to finish in your browser` in the wizard and `Finish authorizing in the GitHub browser window. Admin will check again when it closes.` in Admin. One addition, because a lost browser window is the common failure: `Didn't see the browser? Open it again.` with the action beside it. There is no timer and no count, and the existing expiry copy (`That code expired.` with `Get a new code`) continues to own the ending.

### 8. Motion

Motion here has one job: to be the only thing on screen that distinguishes *alive* from *stopped*. Everything else is text and shape, so motion is spent carefully and removed the instant it would lie.

| Moment | Technique | Timing |
|---|---|---|
| A row starts working | indicator fades in on that row only | 120 ms |
| A row resolves | glyph cross-fades, text swaps | 150 ms |
| Finished rows collapse into the roll-up | height transition | 200 ms ease-out |
| The bar advances | width follows the count | 250 ms ease-out, no shimmer |
| The run stalls | all motion stops, glyph cross-fades in | 150 ms |
| First paint of a known list | rows appear together, no stagger | none |

If the animation were removed from a working row, nothing on screen would separate it from a dead one, which is precisely the current defect, so this is the one place in the product where motion is load bearing. No stagger is used on progress lists, because a stagger reads as sequencing that the data does not support. Reduce Motion replaces every transition above with an instant swap and the indeterminate indicator with a static `Working on it now.` label plus the count, which loses nothing, because in this design the words always carry the state.

### 9. Copy rules for this surface

No duration, no countdown, no estimate, no percentage, and no em-dashes. A fraction may only describe work in flight, and never survives the end of that work, so it can never be read as a score. The heading of a running operation never changes while it runs. Every waiting sentence names its subject. Every ended state says plainly what was and was not changed.

## Accessibility

Progress is announced, and it can also be asked for. The announcement covers the person who is not looking; the queryable value covers the person who wants to check without waiting for one.

**Queryable, not just announced.** The progress element is one accessibility element with the label `Setting up your organization` and the value `4 of 16 done`, so it can be read on demand at any moment. Each row is one element combining title, state word, and detail, in that order: "Claude Copilot, for Design, working on it now". The indeterminate indicator carries the label `Working on it now` rather than announcing nothing, and a not-started row announces "not started yet" because the words are really there.

**Announcement policy, throttled on purpose.** Twenty-three announcements in a row is noise, so announcements are spent on changes that change what the person can do. Polite, and never stealing focus: the run starting, with its scope (`Setting up your organization. 16 things to do.`); each row completing when the list has six rows or fewer; only group boundaries when it is longer (organization spaces done, then each department, then the setup file); and the ending summary. Immediate and important, not polite: any failure or refusal, and the stall. A repeating heartbeat is never announced.

**The stall does not steal focus.** It announces at importance, and its two actions join the tab order right after the run's own element, so they are one Tab away without the caret being moved out from under anyone.

**Keyboard.** Tab order on the run surface is: the progress element, then `Show what's done` when present, then any expanded failure row's action, then the footer actions left to right. While the run is alive, the primary is disabled and carries the hint `Setup is running. This finishes on its own.`, so a disabled control is never silent about why. Default-action keyboard behaviour returns to the primary the moment the run ends. `Keep waiting` is the default action in the stall card, so pressing Return does the safe, non-destructive thing.

**Never colour alone, and never motion alone.** Each of the eight row states has its own glyph shape and its own sentence, and the two most consequential ones (not started, no answer) are the two with no motion. With colour removed, shape and text still separate every state; with motion removed, text still separates alive from stopped.

**Contrast.** Row text and state words meet 4.5:1 against the card surface in both appearances; glyph colours are reinforcement only and are never the sole carrier of meaning, so their contrast is not asked to carry the state.

## Architecture decision

Progress is parsed from what the engine already reports, and from the plan the person already approved. The app models no ordering, invents no denominator, and computes no ecosystem state: it attaches each emitted line to the row that line names, keeps the worst result per row, and reconciles the whole list against the run's exit. The count comes from the approved plan, which the app already renders in the Review inventory card, and the denominator grows if the engine mentions something the plan did not.

Six things are needed in the app to hold this up. `WriteState` is replaced by a phase carrying `startedAt`, `lastLineAt`, and the working subject, with `notStarted` and the animated in-flight state on separate, exhaustive branches. The single `ProgressView` construction site takes the in-flight payload as its argument, so no unnamed and no never-started animation can be built. A silence watchdog moves a silent run out of the in-flight phase. `githubChecking` and `githubAuthorizing` booleans go the same way as `WriteState`. `ShellRunner` gains a line-streaming variant, because the current one only reads stdout after `waitUntilExit`, which both prevents streaming and risks a pipe-buffer stall on a chatty run. And the run surface becomes a second state of Review rather than a new surface, so navigation is unchanged.

Two engine-side follow-ons upgrade the same components in place, with no redesign: per-target lines during the read-only plan pass turn the Review inventory card from P2 into P1, and streamed stage lines from the personal apply pass turn the wizard's nested disclosure from P2 into P1. Neither is required for this design to ship, and neither changes any copy above.

Rejected:

- **Keeping one spinner per operation, with better labels.** The audit's finding was not that the labels were weak; it was that a dead operation and a live one drew the same thing. Better words on the same undifferentiated animation would leave that exactly as it is.
- **A determinate bar everywhere, with an invented denominator.** A bar over a guessed total is the same lie as the wizard's timer, with more confidence. The bar survives only where a real, pre-known count exists, and only as the twin of that count.
- **A percentage anywhere.** It reads as a promise about time, which this product has ruled out everywhere else, and it destroys the naming that makes each tick meaningful.
- **Advancing the count by elapsed time between real events, to keep things feeling smooth.** This is precisely what is being removed. A count that moves without work behind it is worse than a count that sits still, because it teaches people to trust it.
- **Cancelling a stalled run.** The engine is additive and safe to run again, and cancelling mid-run buys nothing while implying that something was undone. The recovery is to read GitHub with the setup check, which is authoritative and changes nothing.
- **Moving failed rows to the top.** It breaks the list order the person just read in Review and makes a failure hard to locate in context. Failures instead refuse to collapse, which makes them the only expanded rows once the run ends.
- **Hiding completed rows entirely.** Completed work is the evidence that the run was real. It collapses to a count, and it stays reachable, including after the run ends.
- **Showing the fan-out sweep as a bar in the wizard.** Its projects are discovered inside its own loop, it gates nothing, and giving it a denominator would mean inventing one.

Owner confirmations:

1. **The first determinate bar in the product.** Control Tower has been deliberately bar-free and gauge-free (no score, no ring, no percentage). This design admits one bar, only as the visual twin of an honest count of named work in flight, only above seven rows, and only while the run is alive. Confirm that exception, or the design falls back to the count line alone, which costs nothing but scannability on the largest organizations.
2. **Who runs the mutating setup.** `docs/01-architecture/admin-standup-contract.md` §7.2 supersedes the old "app fires bootstrap and streams rows" model with a baton pass in which the app is blind during execution and Claude Code narrates. The shipped app does not do that: `applyRepositoryPlan` fires the engine directly. This spec follows the code, because a blind app cannot show honest progress at all. Confirm that the app owns execution, and the contract's §7.2 note gets corrected rather than the design.
3. **Blocking defect found while specifying this.** `RepositoryPlanRow` requires `rank`, `package_state`, `package_action` and `package_detail`, which the organization plan engine does not emit, so the Review inventory decode fails, the card shows its failure state, and **Set up organization stays permanently disabled**. Verified by decoding real engine-shaped output. This is a prerequisite fix, not a design decision, and the counted design depends on it because the plan is where the denominator comes from.
