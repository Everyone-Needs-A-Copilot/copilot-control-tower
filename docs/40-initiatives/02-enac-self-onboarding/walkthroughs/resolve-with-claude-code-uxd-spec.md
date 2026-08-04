# Resolve with Claude Code — UX Specification

Status: Phase 9.2 design handoff

Companion: `21-resolve-with-claude-code-uxd-walkthrough.html`

## Service promise

**Resolve with Claude Code** starts one visible, bounded preparation session for
the complete Python-authorized project batch. Claude Code may read the helper's
project summaries and draft proposals. It does not edit live projects, decide
that verification passed, or bypass the reviewed Python apply boundary.

The one button removes setup administration. It does not remove informed
approval. The person still reviews proposals that would change projects,
answers decisions only an owner can make, and confirms one exact plan before
Python applies and freshly verifies it.

## Primary flow

1. The existing default-all project summary remains the entry surface. Every
   Python-authorized safe project and every project with an assistant-ready
   dossier is included by default. Ready projects are acknowledged quietly.
2. The primary action is **Resolve with Claude Code**. Individual project choice
   remains a secondary escape hatch before starting.
3. Control Tower opens one visible Claude Code preparation session. The screen
   moves immediately to **Preparing project proposals** and states **Nothing is
   changing yet**.
4. Progress advances only from real service events: opening the approved batch,
   drafting bounded proposals, and Python validating those proposals. There is
   no invented percentage, timer, or project-complete claim.
5. The result separates:
   - proposals ready for review;
   - owner decisions that need an answer;
   - held projects that remain unchanged; and
   - projects already ready.
6. The person answers each owner decision or chooses **Leave unchanged**.
   Unanswered decisions never enter the plan.
7. **Review proposed changes** opens the existing exact-plan surface using plain
   **Will change**, **Will preserve**, **Will not do**, and **Will check** groups.
8. The person confirms **Apply reviewed changes** once. Python re-inspects,
   applies bounded work, rolls back failures, and records a durable receipt.
9. A separate Python call freshly verifies the same selected batch. The receipt
   reports **Verified**, **Left unchanged**, **Restored**, or **Needs attention**
   per project.

## Default and selection behavior

- Default-all means every project Python explicitly authorizes for this run. It
  never means every folder regardless of safety.
- Claude Copilot and Codex Copilot stay universal. There are no component
  switches or recipe controls.
- **Choose projects individually** shows one checkbox per authorized project.
- The assistant cannot add a project that Python omitted or held.
- Returning to default-all restores the complete Python-authored set.
- The launch action names the exact count: **Resolve 47 projects with Claude
  Code**. It is disabled at zero with the visible reason **Select at least one
  project**.

## Alternate and recovery flows

### Claude Code unavailable

The button does not launch a partial or invisible session. Show:

> **Claude Code is not available on this Mac**
>
> Install or reconnect Claude Code, then try again. No projects were changed.

Actions are **Check again** and **Use standard setup only** when a deterministic
safe batch exists. The standard path preserves the current exact-plan flow and
does not attempt customized projects.

### macOS permission denied

Return focus to an inline decision block:

> **Allow Control Tower to open Claude Code**
>
> In System Settings, allow Control Tower to control Terminal. Then come back
> and try again. No projects were changed.

Actions are **Open System Settings**, **Try again**, and the same standard-only
fallback when available. Do not repeatedly trigger the system prompt.

### Preparation interrupted or unavailable

Preserve the latest Python-authored batch and state what completed. Offer
**Resume preparation** only when the service has durable resumable evidence;
otherwise offer **Start again**. Never label a missing assistant response as a
project failure.

### Owner decisions

Each decision is one plain-language question with radio choices authored or
validated by Python, an optional **Leave unchanged** choice, and a one-sentence
effect. The default is unanswered. Technical evidence sits behind **Why this is
needed**. Decisions are project-scoped and never inferred from another project.

### Held work

Held is protective, not failed. A compact **Left unchanged to protect your
work** section names each project, its plain-language reason, and its next safe
action. Dirty work, unreadable roots, missing sources, and policy holds never
enter assistant preparation, the reviewed plan, or apply.

### Apply, verify, and rollback

- Applying shows one current activity sentence and **Keep Control Tower open**.
- Verification is a visibly separate step after apply.
- A successfully restored project reads **Restored. Your previous project setup
  is back in place.**
- Incomplete restoration is the only rollback state styled as blocked and must
  expose the Python-authored next action plus diagnostic location.
- One project failure never erases successful peer receipts.

## Product language

Customer-facing screens do not use **schema**, **fingerprint**, **recipe**,
**dossier**, **ledger**, **migration**, **operation ID**, or **rollback target**.
Use:

- **project summary**, **proposal**, **reviewed changes**, **receipt**;
- **Preparing**, **Ready to review**, **Needs your decision**;
- **Left unchanged to protect your work**, **Restored**, **Freshly verified**.

Claude Code is credited only with proposal preparation. Python-authored apply
and verification truth is spoken as **Control Tower checked** or **The latest
check found**, never **Claude Code fixed**.

## Accessibility

- The primary button announces the exact included count.
- On launch, focus moves to **Preparing project proposals**. Status changes use
  a polite live region; individual project events do not repeatedly interrupt.
- A spinner is always paired with text. No progress fact depends on animation.
- When proposals arrive, focus moves to **Proposals ready to review** and the
  count summary is announced once.
- Decision groups use native radio semantics, programmatic project headings,
  and explicit validation text. The first unanswered decision receives focus
  after an attempted continue.
- Held, decision, verified, restored, and blocked states always use icon shape
  plus text. Color is redundant.
- Permission denial returns focus to its inline heading. **Open System
  Settings** has the hint **Opens Privacy & Security settings**.
- Exact-plan disclosures and receipts remain keyboard reachable; collapsed
  technical detail never hides the primary outcome or next action.
- Reduced Motion removes progress transitions. Increase Contrast and VoiceOver
  retain the same hierarchy and wording.

## Dependencies and non-negotiable boundaries

- Python must author the eligible assistant batch, project summaries, owner
  decision choices, held reasons, validated proposals, exact plan, outcomes,
  next actions, and diagnostic references.
- Claude Code must be constrained to proposal generation. It receives no
  authority to write selected projects directly.
- Control Tower owns presentation, explicit person choices, focus, and the
  visible assistant launch. It does not derive eligibility or success.
- If the assistant, Python validator, or contract is incompatible, the flow
  fails closed and the deterministic standard-only path remains available when
  Python says it is safe.
