# Product brief — Copilot Control Tower

**The why: democratization.** The Copilot ecosystem gives a deeply technical person real superpowers — write well, check the numbers, build software that does parts of the job, integrate data across sources. But those superpowers are locked behind terminal fluency almost no one has. Control Tower is the one-click bridge that hands a non-technical person (the "Bob" persona) a technical person's AI superpowers — **safely, and unattended** — so they can break out of *only ever using the software IT handed them*, without understanding the technical layers underneath. It **keeps your environment Copilot-ready**: an authorized change made once upstream simply finds its way onto the machine, quietly, on a cadence, without clobbering personal work.

Content inherits down a four-tier model — **foundation → org → department → personal** — where the org and department tiers are *writable by trained, gated authors* (via a markdown editor) and everyone else reads/pulls on a cadence.

**Observability and honest self-heal are the mechanism, not the headline.** They are what *earn the right* to run in the background on someone else's machine: an always-on, token-holding auto-updater is only trustworthy if every pull is visible, verified, and its status never lies. Democratization is the point; supervision is what makes it safe enough to leave unattended.

Control Tower delivers this as **two faces over one open-source binary**:

- **Operator mode** — a macOS menu-bar app that gives Bob a working, focus-scoped Copilot partner from one double-click, then keeps the machine synced and self-healed for as long as it runs.
- **Admin mode** — a guided, open-source tool that lets an IT team stand up and deploy the whole ecosystem for their org: seed generator, repo/team/secret-store scaffolding, preflight validation, deployment runbooks. Entitlement + deployment is GitHub repo access, not device management.

> **Evidence honesty.** Claude Copilot delivering value to a team is **real and tested** (several users on the owner's team). The Admin / IT-operator experience (repo/team scaffolding, entitlement, deprovision) and the multi-writer org/dept authoring loop are **as-yet-unvalidated hypotheses** — no real IT operator has run Admin mode, and the propagation loop has never run with more than one writer.

## Control tower, not the pilot

The name is the model. A control tower doesn't fly the plane — it watches every flight, keeps them coordinated and on schedule, clears them to proceed, and raises the alarm when something's off. Control Tower is that supervisor role over the ecosystem's `copilot`/`cc` CLI, never a second brain that reimplements what the CLI already does.

## The one invariant

**Control Tower parses; it never computes.** Every health verdict, resolution decision, signature check, prune, and wipe is performed by the CLI — the same hardened pipeline a headless developer runs by hand. If Control Tower vanished, the CLI would still be correct. That contract is what makes an always-on, auto-pulling agent *safer* than a human running `copilot update` manually: nothing about the GUI's presence changes what's true or what's safe.

## What Control Tower syncs

Control Tower keeps four CSE components current at every layer a user is entitled to: **Knowledge
Copilot** (the knowledge layer), **CLI Copilot** (the integration layer to systems outside the
computer), and the **Claude Copilot** / **Codex Copilot** instruction layer. All four sync the same
way, pull-only and downward across foundation → org → department → personal; none of them is a
"products" picture, and none is more managed than another.

## Host-awareness

Within the instruction-layer half of that set, Control Tower detects and manages **Claude Copilot**
and/or **Codex Copilot** independently on a given machine — zero, one, or both may be present. It
has no hard-coded component knowledge beyond detection and column selection; the CLI's `derive` step resolves the rest.

## Non-goals

- **Not a second brain.** No resolution logic, no health scoring, no signature verification lives in the app — that would duplicate a hardened pipeline and create two sources of truth.
- **No independent decision-making about systems of record.** Reads happen unprompted; writes confirm.
- **Windows is deferred**, not designed against — macOS-first, Windows is a later re-skin.
- **Does not replace systems of record** (GitHub, Teams/HR directories) — it supervises and surfaces state that already lives there.
- **Not a project/product manager.** A product/project (e.g. Insights Copilot, Pipeline, Method) carries its own knowledge/skills/agents/integrations inside its own repo, standardized by the Copilot instruction layer when you work in it. It is never a Control Tower sync layer.

For the full validated architecture — the status model, process model, the app↔CLI contract, distribution/signing, Admin mode, and the escalation model — see [`../01-architecture/architecture.md`](../01-architecture/architecture.md).
