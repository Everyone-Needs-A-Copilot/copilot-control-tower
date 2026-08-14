# ADR-010 — Initiative 06 proves technical ecosystem readiness first

Status: Accepted Date: 2026-08-14 Decision owner: Pablo Alejo Supersedes: the human-validation completion gate and the corresponding rejected alternative in ADR-009

ARTIFACT: architecture-decision ARTIFACT: scope-decision ARTIFACT: dependency-check

## Context

Initiative 06 originally combined three different kinds of proof: technical ecosystem readiness, long-term use by Pablo, and a non-technical person's experience through Control Tower. That made framework completion depend on an application Pablo does not currently want to use and on lived-use evidence that can only emerge after the technical system is stable enough to dogfood.

The product direction in `SOUL.md` remains valid: the eventual ecosystem should make high-quality solution creation accessible to ordinary people. The current delivery sequence changes because Pablo needs to use the underlying system directly before deciding what the app should become.

## Decision

- Initiative 06 now owns technical ecosystem readiness for direct use through Claude Code and Codex.
- Control Tower source, packaging, signing, notarization, installation, supervision, and app-specific experience proof are outside Initiative 06. The deferred app work remains preserved in PRD-24 and does not automatically resume when Initiative 06 completes.
- A non-technical participant study and long-term dogfooding are not Initiative 06 completion gates. They are future product-validation work after technical readiness.
- Clean-environment proof remains mandatory because it establishes that the technical system does not depend on Pablo's current machine state, hidden caches, or manual repository wiring.
- Realistic problem-to-solution scenarios remain mandatory. They prove the technical chain from problem intake through specialist assembly, application, artifact creation, preservation, continuation, and update.
- Behavioral evaluation remains bounded. It must show attributable effects from organization and department inputs without claiming that the entire product outcome has been achieved.
- The Initiative 06 completion verdict is **technically ready for owner dogfooding**, not **the democratization goal is complete**.

## Active completion graph

```text
owner governance and scope
          |
          v
framework + organization + accounting releases
          |
          v
exact runtime installation and signed layer resolution
          |
          v
technical component and scenario suite
          |
          v
zero-S0 conformance + reviewed residuals + integrated security
          |
          v
approved propagation + post-propagation verification
          |
          v
clean-environment technical proof
          |
          v
final technical-readiness audit
          |
          v
Pablo dogfoods the ecosystem; future app/product validation follows separately
```

## Consequences

- TASK-303 remains an active technical gate.
- TASK-290 is reclassified as future product validation and removed from TASK-292's completion dependencies.
- TASK-292 audits only the active technical contract.
- Existing app work products remain intact under PRD-24; they cannot be cited as Initiative 06 proof and do not block it.
- A technically complete Initiative 06 is sufficient to begin real work with the ecosystem. It is not sufficient to claim that a non-technical person can use it successfully or that Control Tower solves setup and supervision.

## Fitness functions

- No active Initiative 06 task depends on an app-build, Apple-publisher, app-installation, app-supervision, or non-technical-participant task.
- The technical plan contains explicit Claude Code and Codex scenarios for problem intake, assembly, application, creation, preservation, continuation, update, recovery, and security failure.
- Clean-environment execution records exact framework and layer identities and does not use Control Tower.
- The final report uses the phrase **technically ready for owner dogfooding** only when every active technical gate has linked evidence.

VERDICT: ACCEPTED — BUILD AND PROVE THE TECHNICAL ECOSYSTEM FIRST; DOGFOOD IT NEXT; REVISIT THE APP LATER.
