# Project Integration Aftercare — Live Inventory Analysis

Status: design research
Task: `tc` 184
Evidence date: 2026-07-30
Source: installed Control Tower 0.1.7 embedded `cc`, read-only project inspection

## Why this analysis exists

The current product collapses materially different project states into either
“Ready” or “Existing project setup needs review.” Neither label answers the real
question:

> Is this self-contained project correctly connected to the Copilot ecosystem
> while preserving its own agents, skills, instructions, and integrations?

Control Tower does not sync project contents. Projects remain self-contained.
Its job is to render the CLI’s verified project-integration contract, route safe
work, and recheck the result.

## Current reported inventory

The installed CLI reports 53 projects:

| Current result | Count | What the current result actually proves |
| --- | ---: | --- |
| Ready | 36 | At least one recognized Claude or Codex marker exists |
| Setup available, but blocked | 17 | Neither component is recognized and at least one installer target already exists |

The current “Ready” test is too broad:

| Recognized components | Count | Projects |
| --- | ---: | --- |
| Claude and Codex | 31 | Includes highly customized, correctly integrated projects such as `pipeline-copilot` |
| Claude only | 1 | `h3` |
| Codex only | 4 | `convoco-policy-build`, `convoco-site`, `insights-copilot`, `knowledge-copilot-internal` |
| Neither recognized | 17 | The existing warning group |

Five projects therefore appear ready even though one recommended copilot is not
recognized.

## The 17 blocked projects are not one use case

Read-only inspection of the actual collision targets produces these patterns:

### Compatible Claude setup without current proof

Representative projects:

- `admin-server`
- `flow`
- `lars-website`
- `n8n-copilot`
- `product-creation-copilot`
- `project-copilot`
- `rfp-copilot`
- `the-collective`

These projects contain current core Claude framework files plus valuable
project-local instructions, but lack the marker combination the CLI uses as
installation proof. They are candidates for a safe “confirm existing setup and
add the missing component” path. The CLI must make the final determination.

`admin-server` is important because its local `CLAUDE.md` contains critical data
protection and backup rules. Any path that replaces it is unacceptable.

### Project guidance without shared framework integration

Representative projects:

- `cli-copilot`
- `crm-automation-copilot`
- `drip-copilot`
- `workflow-copilot`

These projects contain a project-specific `CLAUDE.md`, but not a complete
recognized Claude integration. Codex may be mechanically addable, while Claude
requires a semantic merge that preserves the existing project guidance.

### Specialized or older Claude ecosystems

Representative projects:

- `cli-copilot-internal`
- `preflight-copilot`

`preflight-copilot` has 24 project agents, eight project skills, and eight
commands, but does not contain the current shared framework entry points.
This is not a filename collision; it is a genuine guided-integration case.

### Existing Codex setup without current proof

Representative project:

- `codex-copilot`

The project contains `AGENTS.md`, the Codex Copilot plugin, skill bridge, gate
script, and marketplace declaration, but lacks the current metadata marker. This
is a candidate for safe adoption followed by a safe Claude addition.

### Mixed Claude and Codex customization

Representative projects:

- `research-copilot`
- `transformation`

`research-copilot` contains a large, older Claude operating model, a separate
project-specific `AGENTS.md`, current Claude framework agents, and a Codex skill
link without the complete plugin setup.

`transformation` contains a compatible Claude framework plus a five-line
Next.js-specific `AGENTS.md` rule block. The correct integration must retain that
rule while adding the shared Codex entry point.

## Customized and already integrated

`pipeline-copilot` is the positive control:

- both Claude and Codex are recognized;
- `CLAUDE.md` contains pipeline-specific commands, writing agents, legal agents,
  and operating rules;
- `AGENTS.md` activates both the shared Codex Copilot plugin and a project-local
  Pipeline Copilot plugin;
- project-specific skills remain inside the project;
- shared framework entry points and verification markers coexist with those
  customizations.

Customization should therefore never imply “needs review.” The relevant question
is whether the customization satisfies the project-integration contract.

## Candidate target classification

The richer CLI contract does not exist yet, so this is a design-research
classification, not an executable verdict:

| Target experience group | Candidate count | Basis |
| --- | ---: | --- |
| Customized or standard, verified complete | 31 | Both components currently recognized |
| Can likely be finished safely | 11 | Compatible existing framework or recognizable legacy setup |
| Needs guided integration | 11 | Project entry-file conflict, specialized legacy setup, or mixed customization |

The CLI may move individual projects between the last two groups after
content-aware, fail-closed preflight. The app must not compute these groups.

## Use cases the walkthrough must cover

1. **Customized and integrated:** `pipeline-copilot`; no change required.
2. **Compatible existing setup:** `admin-server`; confirm/adopt without replacing
   safety rules, then add the missing component.
3. **Recognizable legacy Codex setup:** `codex-copilot`; record existing setup and
   add Claude.
4. **One component ready, other component customized:** `h3` or
   `convoco-policy-build`; guide only the missing component.
5. **Project guidance only:** `crm-automation-copilot`; preserve the existing
   project guide while adding ecosystem entry points.
6. **Deeply specialized project:** `preflight-copilot`; generate an agent-guided
   integration plan for local agents and skills.
7. **Mixed customization:** `research-copilot` or `transformation`; reconcile
   both Claude and Codex without flattening project rules.
8. **Non-owner user:** prepare an actionable handoff instead of a technical
   prompt.
9. **Agent needs a decision:** return an explicit unresolved choice, preserve all
   files, and re-run verification after the owner decides.
10. **Verification succeeds:** move the project to Ready and retain
    “Project-specific setup” as a positive fact.

## Important boundary

The proposed prompt is not authored by Control Tower. The CLI produces a
structured, project-specific integration plan and prompt from its verified
inspection. Control Tower can open Claude Code or Codex with that prompt, copy it,
or package it for the project owner. The external coding agent performs semantic
project-local work. The CLI verifies afterward.
