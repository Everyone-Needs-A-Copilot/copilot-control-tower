# User-controlled project handoff — service specification

## Job to be done

When many projects need different Claude or Codex integration work, the person
wants one understandable handoff from the Sites folder, so they can use one
normal coding-assistant conversation without visiting every project or giving
Control Tower control of that conversation.

## Service concept

Control Tower prepares the work; the person controls the conversation; Python
checks the result. The app writes one immutable work order and one short prompt,
opens an ordinary Terminal window at the approved Sites root, and explains how
to start Claude Code or Codex. It does not start either assistant, paste the
prompt, observe the conversation, or infer progress from it.

This direction is intentionally narrower than the previous guided-session
design. It follows the product's “as little app as possible” and “second pilot”
boundaries: Control Tower is a trustworthy handoff and verifier, not an agent
runner.

## Journey and responsibilities

| Stage | Person sees or does | Control Tower | Python helper | Coding assistant |
|---|---|---|---|---|
| Select | Reviews one included batch | Renders Python's selection | Excludes unsafe and ecosystem repositories | Not running |
| Prepare | Chooses **Prepare instructions** | Requests one package | Writes the exact work order and copy prompt | Not running |
| Open | Receives a normal Terminal at Sites | Opens the folder only | No lifecycle claim | Not running |
| Start | Types `codex` or `claude`, copies the prompt, and pastes it | Shows the steps and prompt | Supplies the file the prompt references | Starts only because the person chose to start it |
| Work | Talks to the assistant and answers genuine questions | Does not watch, poll, or interpret | Provides exact per-project checks in the work order | Inspects, changes, asks, and verifies sequentially |
| Check | Returns and chooses **Check the projects** | Invokes a fresh final check | Verifies the complete selected batch | Cannot self-approve |
| Finish | Sees verified or remaining projects | Renders the report | Owns every readiness claim | May be resumed manually with the same prompt |

## Failure and recovery paths

- If Terminal cannot open, the work order and prompt remain available. The app
  gives the exact Sites path and tells the person to open Terminal there.
- Claude Code or Codex does not need to be detected before preparation. The
  person may install, sign in to, or switch assistants without recreating the
  work order.
- If the assistant stops, crashes, or asks a question, Control Tower does not
  display a spinner or invent a status. The person continues the normal
  conversation or returns later.
- If a final check finds remaining work, the same prompt and work order stay
  available. Nothing is rolled back merely because verification is incomplete.
- Dirty or unsafe projects remain outside the authorized work list. The work
  order requires the assistant to stop and ask before touching newly dirty work.
- If the package changes after Python creates it, Python rejects it before any
  result is trusted.

## Service constraints

- The work order and prompt may contain approved project paths and non-secret
  inspection facts. They contain no credentials or project file contents.
- The Terminal handoff opens only the first approved root. Additional approved
  roots remain named inside the Python-authored file.
- The app never composes project instructions or decides readiness.
- The user's assistant conversation is not a child process or lifecycle owned
  by Control Tower.

## Alternatives rejected

- Automatically launching Claude Code or Codex with the work order: removes the
  person's control and creates an opaque, non-interactive experience.
- Pasting or executing a command automatically: makes the app the session
  operator and hides the moment authority changes hands.
- Polling the guide while the user works: implies visibility into the
  conversation and produces an unhelpful spinner when no reliable progress is
  available.
- One session per project: unacceptable cognitive and operational load.
- An in-app chat surface: makes Control Tower a second pilot.
- Trusting the assistant's completion statement: violates evidence honesty.

