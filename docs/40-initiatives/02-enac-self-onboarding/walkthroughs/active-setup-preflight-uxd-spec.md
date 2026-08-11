# Active Setup Preflight — UX Specification

Status: owner-directed; implementation task `tc` 255

Companions:

- `25-active-setup-preflight-uxd-walkthrough.html`
- `26-active-setup-preflight-uids-walkthrough.html`

## Product decision

Project setup begins with action, not a passive census. Once GitHub is signed
in and at least one projects folder is approved, Control Tower asks Python to
run one bounded preparation operation before showing project choices:

1. save eligible current product-project work in local commits;
2. download clean fast-forward updates for shared Copilot setup;
3. run a fresh assessment over the resulting state.

Swift does not run Git, infer eligibility, combine ledgers, or declare success.
It renders the versioned CLI result.

## Preservation and authority boundaries

- A project checkpoint is local. It is never pushed.
- The CLI creates an ordinary local commit while disabling repository and
  filesystem-monitor hooks for this unattended operation. It still honors Git
  identity and signing policy and fails closed on conflict state.
- Ignored files remain ignored. A sensitive or unreadable candidate fails
  closed. A failed checkpoint leaves project content intact and returns an
  exact hold.
- Ecosystem repositories are never included in project checkpointing.
- Shared Copilot repositories are pull-only in this flow. Only a clean,
  merge-base-proven fast-forward may run, followed by `HEAD == target` proof.
- GitHub repository permission is fresh, explicit evidence. `READ` and
  `TRIAGE` are read-only; `WRITE`, `MAINTAIN`, and `ADMIN` are author-capable;
  missing or unreadable permission is read-only.
- Author capability never turns this preflight into a publish action. Shared
  writes require a separate explicit, governed author workflow.

## Primary flow

1. The person enters **Your projects**.
2. Control Tower immediately shows **Getting your projects ready** with three
   ordered activities: saving local work, downloading shared setup updates,
   and checking current project setup.
3. The CLI returns a completed-actions ledger and a fresh assessment.
4. The screen leads with the receipt: **I saved work in N projects and
   downloaded M Copilot updates.** Zero-count actions are omitted rather than
   phrased as accomplishments.
5. The project batch then shows only what remains: ready, safely handleable,
   and genuinely decision-bound projects.
6. If everything routine is complete, the main sentence is **The routine work
   is done.** The next action describes only the remaining human decision.

## Alternate and recovery states

- **Nothing needed:** no receipt is invented. Say **Your projects and shared
  Copilot setup are current.**
- **Checkpoint held:** say **I saved the work Git allowed me to save.** Name
  the projects that still need the person and the plain reason. Never recommend
  discarding work.
- **Shared repository dirty/diverged:** leave it untouched. Say **I found
  changes in shared Copilot setup, so I left that repository alone.** Route it
  to an authorized maintainer.
- **GitHub permission unavailable:** treat the repository as read-only and
  continue pull-only work where read access and Git history are proven. Never
  expose a publish affordance.
- **Offline:** make no commit merely to improve a count. Preserve current work,
  say the shared update could not be checked, and retain **Check again**.
- **Partial saga:** list completed local commits and fast-forwards from the
  ledger before the exact stopping condition. Never say nothing changed when
  the ledger is non-empty.
- **CLI/schema failure:** show the existing holding surface with the support
  report. Do not reuse stale project counts.

## Product language

- Progress title: **Getting your projects ready**
- Progress detail: **I’m saving current project work locally, downloading the
  latest shared Copilot setup, and then checking what remains. Nothing is
  pushed.**
- Success receipt: **I saved work in 12 projects and downloaded 4 Copilot
  updates.**
- Routine-complete title: **The routine work is done.**
- Remaining-decision detail: **Two projects contain setup I can’t safely choose
  for you. I left them unchanged.**
- Read-only disclosure: **Shared Copilot setup is download-only here.**
- Retry: **Check again**
- Primary continuation: **Review the remaining projects** or **Continue setup**
  when no project work remains.

Do not use **Protected work** as the primary diagnosis after a routine dirty
tree. Do not say **No projects can be changed safely right now** when the CLI
has not first attempted the owner-approved checkpoint preflight.

## Accessibility

- Focus enters the progress heading once; each completed activity is announced
  once through a polite status region.
- The receipt is a semantic summary, not color-only status.
- Every held project combines its name, preservation result, reason, and next
  action in one accessible element.
- Read-only versus author-capable is never represented solely by an icon.
- Reduced-motion replaces indeterminate animation with static **Working…**
  text while preserving announcements.
- A retry returns focus to the progress heading; completion moves focus to the
  fresh project-summary heading.

## Resolved design decisions

- Service design is skipped: the owner specified the service behavior and the
  change is bounded to the existing setup journey.
- Project checkpointing is automatic but local-only and fail-closed.
- Shared ecosystem updates are automatic pull-only fast-forwards.
- GitHub grants author capability; filesystem writability and a configured Git
  remote do not.
- The existing Step 7 card structure remains. This work adds a preparation
  state and a ledger-backed receipt rather than a new dashboard.
