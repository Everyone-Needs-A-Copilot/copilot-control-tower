# Before you begin: what standing up your organization needs

|  |  |
|---|---|
| **Audience** | An operator standing up their company's copilots for the first time (the app calls this person the Admin). No prior experience with Control Tower assumed. |
| **Diataxis mode** | How-to (task-oriented: get ready for org setup). This page does not teach the ecosystem model (see the app's own Orientation screen and [`docs/10-reference/copilot-solutioning-ecosystem.md`](../10-reference/copilot-solutioning-ecosystem.md) for that), and it is not the full walkthrough of the setup itself (see [`docs/03-design/admin-experience-service-design.md`](../03-design/admin-experience-service-design.md) for the full journey). Its one job: tell you what has to be true before you start, and why GitHub access setup asks for what it asks for. |
| **Reads on** | [`docs/01-architecture/admin-standup-contract.md`](../01-architecture/admin-standup-contract.md) (the fail-closed plan/apply/verify contract) and [`admin-first-two-machine-setup-runbook.md`](admin-first-two-machine-setup-runbook.md) (the complete operator sequence). |

## What you need before you start

Admin checks the software and GitHub access itself. You do not install Homebrew,
GitHub CLI, `jq`, Python, or Claude Code for the Admin flow, and you do not run
prerequisite commands.

Three owner-controlled facts still have to be true:

1. **Your GitHub organization already exists.** Creating an organization is a
   billing and ownership decision, so Admin does not invent one.
2. **Your GitHub account is an active Owner of that organization.** Admin checks
   this through GitHub and opens the organization settings if another owner must
   grant the role.
3. **The organization has an OAuth App with device flow enabled.** Admin opens
   the correct GitHub settings page. Paste only the public 20-character Client
   ID into Admin; never paste the client secret.

## What GitHub access setup needs, and why

Setup creates your organization's shared repositories and sets up your teams and their access. To do that, the GitHub command-line tool needs two permissions, called scopes:

| Scope | What it is for |
|---|---|
| `repo` | Lets setup create the repositories where your organization's copilots, knowledge, and tools live. |
| `admin:org` | Lets setup create your teams, grant them access to the right repositories, and set your organization's base permission. |

Setup never needs more than these scopes. Select **Authorize GitHub** in Admin
when asked. Admin opens GitHub's browser authorization and checks the result
again when it closes. No command is displayed or copied.

## A note on plans

Setup asks GitHub to require a review before your organization's shared setup files change. For private repositories, GitHub only offers that protection on a paid plan. If your organization is on GitHub's free plan, setup still finishes and your spaces are still created. The review-protection step is simply skipped until you upgrade.

## What happens next

Double-click **Copilot Control Tower Admin**. It checks readiness automatically,
collects a non-secret organization description, reads GitHub to show the exact
private repositories it will create or reuse, and waits for **Set up
organization**. That button repeats the full preflight before making additive,
idempotent changes. **Setup check** then reads GitHub again from scratch. Follow
[`admin-first-two-machine-setup-runbook.md`](admin-first-two-machine-setup-runbook.md)
for the complete sequence.

## Security note

Control Tower never asks for a GitHub token, OAuth client secret, or integration
secret. GitHub's own browser flow stores the resulting credential using GitHub
CLI's normal secure credential mechanism. Admin invokes its packaged,
checksum-pinned tools and deterministic engine only after explicit
confirmation. It creates only confirmed-missing private repositories, reuses
existing private repositories, and blocks on public, unreadable, or unfamiliar
content instead of overwriting it.
