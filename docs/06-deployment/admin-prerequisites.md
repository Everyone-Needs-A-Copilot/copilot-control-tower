# Before you begin: what standing up your organization needs

|  |  |
|---|---|
| **Audience** | An operator standing up their company's copilots for the first time (the app calls this person the Admin). No prior experience with Control Tower assumed. |
| **Diataxis mode** | How-to (task-oriented: get ready for org setup). This page does not teach the ecosystem model (see the app's own Orientation screen and [`docs/10-reference/copilot-solutioning-ecosystem.md`](../10-reference/copilot-solutioning-ecosystem.md) for that), and it is not the full walkthrough of the setup itself (see [`docs/03-design/admin-experience-service-design.md`](../03-design/admin-experience-service-design.md) for the full journey). Its one job: tell you what has to be true before you start, and why GitHub access setup asks for what it asks for. |
| **Reads on** | [`docs/01-architecture/admin-standup-contract.md`](../01-architecture/admin-standup-contract.md) (the preflight auth model this page explains in plain language) and [`.claude/skills/admin-bootstrap/SKILL.md`](../../.claude/skills/admin-bootstrap/SKILL.md) (the terminal side that checks the same things). |

## What you need before you start

Three things have to be true before setup can run. None of them happen in Control Tower itself. This is so nothing stops you halfway through.

1. **Your GitHub organization already exists.** Creating a GitHub organization needs billing and a person, so it is not something setup can do for you. If your organization does not have one yet, create it at github.com first, then come back.
2. **You are an Owner of that organization.** Only an Owner can create the organization's shared spaces (its repositories and teams). If you are not sure, check your role on github.com, or ask whoever administers your GitHub organization today.
3. **You have GitHub's command-line tool (`gh`) and Claude Code installed on this Mac.** Setup runs through both. If either is missing, the app's Connect GitHub step tells you and helps you install it.

## What GitHub access setup needs, and why

Setup creates your organization's shared repositories and sets up your teams and their access. To do that, the GitHub command-line tool needs two permissions, called scopes:

| Scope | What it is for |
|---|---|
| `repo` | Lets setup create the repositories where your organization's copilots, knowledge, and tools live. |
| `admin:org` | Lets setup create your teams, grant them access to the right repositories, and set your organization's base permission. |

Setup never needs more than these two scopes. And whatever it does with them, it only ever adds and updates. It never deletes or overwrites anything already there.

To grant both scopes at once, run:

```
gh auth refresh -s admin:org -s repo
```

You do not need to memorize this. The app's Connect GitHub step and the `admin-bootstrap` skill in your terminal both check for these scopes automatically, and if either is missing, they hand you this exact command to run.

## A note on plans

Setup asks GitHub to require a review before your organization's shared setup files change. For private repositories, GitHub only offers that protection on a paid plan. If your organization is on GitHub's free plan, setup still finishes and your spaces are still created. The review-protection step is simply skipped until you upgrade.

## What happens next

Once you are ready, the app collects a plain description of your organization, writes it to a non-secret brief on your Mac, and hands you a single command to run in your terminal. Claude Code reads that brief, confirms the plan with you by real repository and team names, and drives the setup. When it says it is done, you come back to the app and run the Setup check, which reads your organization's state straight from GitHub. See [`docs/03-design/admin-experience-service-design.md`](../03-design/admin-experience-service-design.md) for the full journey, stage by stage.

## Security note

Control Tower never asks for or holds any GitHub secret or token. You authenticate with GitHub yourself, using `gh`. The app only ever runs read-only checks against your GitHub account and organization, and writes a plain, non-secret brief describing what you want set up. The work that changes GitHub, creating repositories, teams, and grants, happens only in your terminal, driven by Claude Code, never by the app itself.
