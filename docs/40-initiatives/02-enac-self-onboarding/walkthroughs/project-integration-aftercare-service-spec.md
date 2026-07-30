# Project Integration Aftercare — Service Design

Status: walkthrough specification
Task: `tc` 184
Evidence: `project-integration-aftercare-analysis.md`

## Job to be done

When Control Tower discovers a project that already contains Claude or Codex
instructions, help the person correctly connect that project to the Copilot
ecosystem without deleting, flattening, or silently replacing the project’s own
agents, skills, protocols, integrations, or operating rules.

The service is complete only when the project is either:

- verified integrated;
- waiting on one clearly named owner decision; or
- handed to the competent project owner with an actionable integration package.

“Owner will review” without a handoff or route to completion is not a service
outcome.

## Service concept

The preferred concept is **verified project aftercare**:

1. The CLI inspects the project against the expected Claude and Codex integration
   contract.
2. It classifies each component independently.
3. Mechanical, reversible work is offered directly.
4. Semantic reconciliation receives a generated integration plan and prompt.
5. Control Tower launches a visible Terminal session for Claude Code or Codex,
   copies the prompt, or prepares an owner handoff.
6. Control Tower observes the launch lifecycle without interpreting assistant
   output, then asks the CLI to re-verify the project afterward.
7. Project-specific customization remains a visible positive fact.

Control Tower coordinates this process. It does not manage project contents and
does not host an AI chat surface.

## Frontstage states

### Ready with project-specific setup

The project is fully integrated and contains local customization.

Example: `pipeline-copilot`.

Message:

> Ready. Claude and Codex are connected. This project also has its own pipeline,
> writing, and legal agents.

No action is offered.

### Can finish safely

The CLI has proven a bounded mechanical action:

- add a missing proof marker;
- record an exact recognized legacy setup;
- add a non-colliding missing component;
- repair a known framework link.

Example: compatible `admin-server` Claude setup plus missing Codex setup.

The review states “Will add,” “Will preserve,” and “Will not change.”

### Guided integration required

The project’s existing instructions overlap with a required ecosystem entry
point, or its custom agent/skill model requires semantic understanding.

Examples:

- `crm-automation-copilot`: project-specific `CLAUDE.md` without shared framework
  integration;
- `preflight-copilot`: 24 agents and eight project skills in an older model;
- `research-copilot`: separate custom Claude and Codex operating documents;
- `transformation`: compatible Claude plus a Next.js-specific `AGENTS.md`.

The person chooses:

- Open in Codex;
- Open in Claude Code;
- Copy integration prompt;
- Prepare handoff for project owner.

### Owner decision required

The external agent found an overlap that cannot be resolved safely without
project intent. All files remain preserved. The result states the precise
decision and offers “Resume guided integration” after the owner decides.

### Could not verify

The project is not marked ready. The UI renders the exact component-level
evidence that could not be proven and offers a retry only when retry can change
the outcome.

When the CLI cannot safely produce an integration plan, it may instead return a
read-only diagnostic payload. Control Tower can launch that payload in a visible
Codex or Claude Code Terminal session. The session may inspect and explain the
mismatch; it may not change project files. Its outcome must return to CLI
classification before any guided write route is offered.

## Frontstage/backstage map

| Stage | Person sees | Control Tower | CLI | External coding agent |
| --- | --- | --- | --- | --- |
| Inspect | Checking Claude, Codex, project-specific setup | Invokes and renders | Computes component contract | — |
| Classify | Ready, safe finish, or guided integration | Renders exact result | Returns structured reason, actor, action | — |
| Safe finish | Exact additions and preservation | Invokes declared action | Applies and records bounded changes | — |
| Guided plan | Detected, required, preserve, verify | Renders plan | Generates structured prompt and verification command | — |
| Launch/handoff | Open a visible Terminal session, copy, or prepare owner request | Starts the selected assistant in the project and reports process lifecycle | Supplies prompt or diagnostic payload | — |
| Integrate | Work happens visibly in the project | Reports running/ended; does not interpret assistant text | — | Understands and edits project-local semantics |
| Verify | Passed, decision needed, or could not verify | Invokes and renders | Verifies the complete project contract | Reports work/decision |

## Generated prompt contract

The prompt payload must contain:

- project identity and path;
- expected Claude and Codex contract versions;
- recognized setup and proof;
- exact missing requirements;
- project-specific files, agents, skills, and protocols to preserve;
- prohibited actions, including overwrite and deletion;
- allowed bounded actions;
- verification command;
- stop conditions requiring an owner decision.

The app may display, copy, or pass through this payload. It does not compose the
technical judgment.

## Read-only diagnostic payload

For `could-not-verify`, the CLI may provide a separate diagnostic payload
containing:

- project identity and path;
- capability summary;
- component-level recognized and missing evidence;
- mismatch, unreadable, missing, or boundary reason;
- explicit read-only constraint;
- prohibited project writes;
- the authoritative verification command;
- the return route for reclassification.

The app may display or pass through this payload. It must not derive one from raw
evidence or silently convert diagnosis into an integration plan.

## Actor routing

| Situation | Competent actor | Experience |
| --- | --- | --- |
| Reversible exact-match adoption | CLI | One-click safe finish |
| Semantic project reconciliation, current user is an authorized author | Project author with Claude/Codex | Open guided session |
| Semantic reconciliation, current user is not an author | Project owner | Copy or send owner handoff |
| Framework/policy incompatibility | Ecosystem owner | Hold safely with support package |
| Personal project decision | Person | Ask only about their own project data |

## Failure and recovery

- External assistant is unavailable: name it, state that nothing changed, keep
  the generated payload, and offer the other installed assistant, Copy, or Retry.
- Terminal launch succeeds but cannot be observed: report the uncertainty and
  require an explicit Check project action rather than inferring completion.
- Agent exits without verification: project remains “Integration incomplete.”
- Verification finds missing requirements: reopen the plan with only remaining
  items.
- Agent detects ambiguous overlap: preserve both versions, stop, and request a
  named decision.
- Project changes after inspection: invalidate the old plan and inspect again.
- Permission is lost: keep the project unchanged and prepare an owner handoff.

## Rejected alternatives

- Treat every custom file as a blocker.
- Treat any customization as already integrated.
- Overwrite `CLAUDE.md` or `AGENTS.md` with a template.
- Put a chat model inside Control Tower.
- Ask Bob to interpret agents, skills, links, or instruction precedence.
- Mark a project ready when only one recommended copilot is recognized.
- End the journey at “Owner will review” without an actionable handoff.
