# User Setup feedback — UX specification

> Task: `TASK-179`
>
> Stage: UX design
>
> Service-design work product: `WP-263`

## Outcome

A non-technical person can move through connections, projects, setup, and
verification without interpreting a catalog, guessing what a count means, or
diagnosing an unexplained failure. Every screen answers:

1. What is true now?
2. Is there a decision for me?
3. What happens when I choose?
4. If something did not work, why and what should I do next?

The menu-bar mark is always the supplied aviator-sunglasses silhouette. Status
may add a shape badge, but it never substitutes another base image.

## Journey change

| Current stage | Revised stage | Purpose |
|---|---|---|
| Integrations | **Your connections** | Show only connections proven ready or available to this person. |
| Your projects | **Your projects** | Explain the complete inventory and ask for one explicit selection. |
| Set up | **Setting up your copilots** | Report real work and stop on project failures with cause and recovery. |
| Verify + Done | **Final check / Your copilots are ready** | Turn verified truth into the single completion moment and next-step handoff. |

The successful Verify state absorbs Done. While verification is running, the
stage is **Final check**. Once verified, the same stage becomes **Your copilots
are ready** and offers **Finish setup**. The redundant tenth step is removed.

## 1. Your connections

### Primary task

Understand what can be used now and connect only an account the organization
has actually made available.

### Information architecture

**Title:** Your connections

**Intro:** These are the tools your organization has made available to your
copilots. Ready connections work now. Available connections need you to sign
in.

Two conditional sections:

1. **Ready to use**
   - organization-provided connections that need no personal sign-in;
   - personal connections already authorized;
   - each row says why it is ready: `Connected as pablo@example.com` or
     `Ready through Everyone Needs A Copilot`.
2. **Available to connect**
   - only entries returned as available by the typed CLI contract;
   - every row names the source: `Available through your organization`;
   - every action is live and specific: `Connect Google Workspace`.

Do not render:

- a provider merely because Control Tower could support it someday;
- a disabled Connect button;
- a shared or personal section with no rows;
- Salesforce, Slack, Microsoft 365, Google, or any other example unless the
  CLI says this person can use it.

### States

| State | Rendering | Actions |
|---|---|---|
| Loading | Three still skeleton rows; no provider names | None |
| Ready + available | Both conditional sections | Connect a returned provider; Continue |
| Ready only | **Ready to use** only | Continue |
| Available only | **Available to connect** only | Connect; Continue |
| Empty | `Your organization has not made any connections available yet.` | Continue |
| Unreadable | `Control Tower couldn't read which connections your organization provides.` | Try again; Continue and check later |
| Provider flow active | Row says `Finish connecting in your browser.` | Open browser again |
| Provider flow rejected/expired | Provider-supplied plain-language reason | Try again |

The empty sentence is permitted only when a successful typed report proves an
empty register. A missing or unreadable report uses the unreadable state,
never the empty state.

### Navigation

- **Back** returns to Departments.
- **Continue** advances to Your projects.
- Connecting an account does not navigate away. The row updates in place from
  Available to Ready after the CLI confirms authorization.

## 2. Your projects

### Primary task

Choose which eligible projects Control Tower should set up, with the complete
inventory explained before any checkbox.

### Summary grammar

The summary names every non-zero group:

`53 projects found: 36 already set up, 14 available to set up, and 3 that
can't be set up here.`

Pluralization is exact. If no projects are blocked:

`53 projects found: 36 already set up and 17 available to set up.`

Instruction:

`Select the projects you want Control Tower to set up. Projects that are
already set up won't be changed.`

### Groups

1. **Available to set up**
   - unchecked by default;
   - selectable checkbox;
   - caption: `Copilot can be added here.`
2. **Needs finishing**
   - unchecked by default;
   - selectable checkbox;
   - caption comes from the CLI and explains what remains.
3. **Can't be set up here**
   - read-only;
   - each row includes the CLI-provided reason;
   - if a user action exists, show it inline;
   - if there is no action, say so rather than displaying a dead button.
4. **Already set up**
   - collapsed by default;
   - read-only;
   - disclosure count is included in the complete summary above.

### Selection behavior

- **Select all available** selects only Available and Needs finishing.
- **Clear selection** returns all selectable rows to unchecked.
- Selected count is always visible beside the group heading.
- Primary action:
  - one selected: **Set up 1 selected project**
  - more than one: **Set up 4 selected projects**
  - zero selected: **Continue without adding projects**
- A separate **I don't keep projects on this Mac** action remains only before
  a project folder has been granted. Once a folder is granted, the zero
  selection action is sufficient.

### Empty and permission states

| State | Copy | Action |
|---|---|---|
| No folder | `Choose the folder where you keep your projects.` | Choose folder |
| Empty folder | `No projects are in this folder yet. New projects can be offered later.` | Continue |
| Folder permission lost | CLI reason in plain language | Choose folder again |
| Inventory unreadable | `Control Tower couldn't check the projects in this folder.` | Try again |

## 3. Setting up your copilots

### Running state

Keep the existing honest progress model:

- fixed title;
- real `N of M done` only while work is active;
- one row for the Mac setup;
- one row per selected project;
- no timer, estimate, percentage, or fabricated phase movement.

### Project result grammar

Every unsuccessful project result must carry three structured pieces from the
CLI:

1. **Reason:** why setup did not happen, in user language.
2. **Preservation:** what was not changed.
3. **Recovery:** one next action and its owner.

Rendered pattern:

`Admin Server wasn't set up because Control Tower could not find a supported
project file. Nothing in Admin Server changed. Choose a different project, or
continue without this one.`

The Swift app does not assemble a diagnosis from workspace fields. It renders
the typed reason, preservation sentence, owner, and recovery action.

### Ending states

#### All selected projects succeeded

Advance automatically to Final check.

#### Some selected projects failed

Stay on Set up.

Title: `2 projects are set up. 1 still needs attention.`

The failed row stays expanded. Successful rows collapse under
`2 projects set up`.

Actions:

- primary: the CLI-provided recovery, such as **Choose folder again** or
  **Try Admin Server again**;
- secondary: **Continue without this project**;
- disclosure: **Copy details for support** when the competent next actor is
  support or an organization administrator.

#### Every selected project failed

Stay on Set up and treat the result as systemic.

Title: `None of the 17 selected projects were set up.`

Intro: `Your copilots on this Mac are still safe. Before continuing, check why
project setup stopped.`

Actions:

- **Check project setup** runs a read-only CLI status/recovery verb;
- **Continue without projects** remains available because project setup is
  reversible, optional, and belongs to the user's own data;
- **Copy details for support** is always present.

This state cannot auto-advance to Verify.

#### Main Mac setup failed

Keep the existing Holding route. Project rows that never started read
`Not started because setup on this Mac stopped first.`

## 4. Final check and completion

### Verifying

**Eyebrow:** Final check

**Title:** Checking your setup

**Intro:** Control Tower is checking the setup on this Mac before it finishes.

One named progress row: `Checking Claude, Codex, and your shared setup.`

### Verified, no deferred work

**Eyebrow:** Setup verified

**Title:** Your copilots are ready

**Intro:** Control Tower verified this Mac. Here is what is ready and what
happens next.

Cards:

1. **Ready now**
   - Claude and Codex have the verified organization and personal setup;
   - selected-project outcome, when projects were selected;
   - GitHub connection status.
2. **What happens next**
   - `Open Claude or Codex in a project and work normally.`
   - `Control Tower keeps shared setup current from the aviators icon in
     your menu bar.`
   - `If the icon gains a badge, open it for the one next action.`

Actions:

- primary: **Finish setup**
- secondary: **Show what setup did**
- learning link: **See what you can build**

### Verified with optional/deferred work

Use the same title only when the core doctor verdict and completion rule permit
it. Add a **Still to do** card containing only real deferred items:

- projects the person explicitly continued without;
- an organization connection offered but not connected;
- a shared store explicitly deferred by the CLI.

Each item says whether it can be completed later from the menu bar or requires
the organization administrator. Do not say `Everything checks out`.

### Not verified

Keep the existing honest incomplete/Holding pattern. There is no Finish setup
action and no completion title.

### Finishing

**Finish setup**:

1. persists completion;
2. closes the setup window;
3. opens the menu-bar popover once, anchored to the aviators icon, so the
   person's final instruction and the steady-state surface are connected.

## 5. Aviators status family

Every macOS `NSStatusItem` state uses the exact silhouette from
`src-tauri/icons/aviators.svg`.

| State | Base | Permitted variation |
|---|---|---|
| Healthy/silent | Aviators | No badge |
| Syncing | Aviators | Existing sync shape badge |
| Sign-in needed | Aviators | Existing key badge |
| Waiting/offline | Aviators | Existing clock/cloud badge |
| Attention/failure | Aviators | Existing triangle/bang badge |
| Unreadable | Aviators | Fail-closed badge/treatment |

The Control Tower illustration remains appropriate for the application icon or
wizard illustration. It is never a substitute for the status-item base.

Release acceptance requires:

- source audit of every `NSStatusItem` image assignment;
- fixture render of every badge state;
- real-pixel check of the installed, notarized app's status item;
- assertion that every variant contains the aviators mask.

## Accessibility

- Focus order follows reading order: intro, section, rows, inline row actions,
  footer actions.
- Each connection row is one element: provider, state, source, action.
- Each project checkbox announces project name, eligibility state, reason, and
  selected state.
- Summary text is a heading-level announcement before the project list.
- Setup progress is queryable and politely announces group completion;
  failures announce immediately without moving focus.
- The completion heading receives focus after verification resolves.
- State always uses text and shape; color and motion are secondary.
- Reduce Motion swaps states instantly and keeps all state words.
- Disabled provider actions do not exist.

## Unresolved technical dependencies

1. A typed CLI connection register is required to distinguish ready,
   organization-available, connected, and unavailable providers.
2. Workspace configure must return structured failure reason, preservation,
   recovery action, and recovery owner.
3. The all-project failure must be reproduced in an isolated HOME or through a
   read-only production status seam before implementation changes.
4. Verify and Done consolidation changes the wizard stage count and persisted
   review-stage mapping.
5. The installed status-item discrepancy needs an asset path and release
   artifact audit; source intent alone is insufficient evidence.

## Rejected interactions

- Static examples or disabled provider buttons.
- Preselecting every available project.
- Auto-advancing after every selected project fails.
- A generic `Try again` without a cause.
- Confetti, trophies, bright success green, or an unqualified `Everything is
  ready`.
- A status-specific base icon that replaces aviators.
