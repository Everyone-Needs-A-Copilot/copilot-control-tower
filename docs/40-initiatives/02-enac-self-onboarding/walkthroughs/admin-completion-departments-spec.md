# Admin completion and department management

## Service outcome

An administrator can tell when onboarding is actually complete, leave the workflow intentionally,
and later see the organization’s existing departments before adding another one. The interface
prevents duplicate department slugs before any setup transaction is written or sent to GitHub.

## Service blueprint

| Stage | Administrator sees and does | Control Tower does | Failure and recovery |
|---|---|---|---|
| Verify | Setup check reports GitHub truth. | Renders the bootstrap engine’s verification result. | Blocking or unknown checks keep Continue unavailable. |
| Finish | Done explains the handoff and offers **Finish setup**. | Marks every onboarding row complete and records local completion. | Closing without finishing leaves Done visibly incomplete. |
| Completed | Done is checked, the header says **Onboarding complete**, and **Close Administration** exits the window. | Keeps governance available without implying more onboarding work. | A new governance transaction clears completion until setup is verified again. |
| Review departments | Add a department shows a scannable **Current departments** list. | Loads the saved, verified standup brief without blocking app launch. | Missing saved configuration renders an honest empty state. |
| Add department | Administrator types one department name and selects **Review department setup**. | Derives the repository-safe slug, checks it against existing slugs, then routes directly to Review setup. | Invalid or duplicate names show inline guidance and keep the action disabled. |

## Interaction specification

### Done: ready to finish

- Keep the existing two handoff cards.
- Add a leading status card: **Everything is verified**.
- Primary action: **Finish setup**.
- Selecting it marks Done and all prior onboarding rows complete.

### Done: completed

- Header status: **Onboarding complete**.
- Done remains a green checked row even while selected.
- Status card becomes **Onboarding complete** and points to Governance for later changes.
- Primary action: **Close Administration**.

### Add a department

- First card: **Current departments**.
- Each department is one stable row with its display name and repository slug.
- Empty state: **No departments are set up yet.**
- Second card: **Add another department**, containing one labeled field and one primary action.
- Duplicate copy: **Accounting is already set up. Choose a different department name.**
- Invalid copy: **Use a name with at least one letter or number.**
- Valid preview: **This will add sales without changing Accounting.**
- Primary action: **Review department setup**.

### Existing Describe form

- Duplicate slugs are invalid there as well.
- Continue stays disabled while any non-empty department name is invalid or duplicated.

## Accessibility

- Completion and duplicate state use text plus icon/color.
- Sidebar exposes “done” after Finish setup.
- Current-department rows combine name and slug into one accessible element.
- Validation appears adjacent to the field and the disabled action has an explanatory hint.
- Default-action keyboard behavior remains on the primary action.

## Architecture decision

Use the existing `AdminModel`, saved standup JSON, `AdminCard`, `StepShell`, and navigation stages.
Do not add a second GitHub inventory reader or let the UI compute ecosystem truth. The saved brief
provides display state; the existing Review plan and Setup check remain authoritative before any
mutation and before completion.

Rejected:

- Routing Add a department back through the full Describe → Integrations → Store sequence: too much
  unrelated repetition for a governance transaction.
- Hiding existing departments in prose: it requires recall and does not scale.
- Allowing a duplicate through and relying on GitHub/setup to no-op: the administrator deserves an
  immediate, local explanation before review.

