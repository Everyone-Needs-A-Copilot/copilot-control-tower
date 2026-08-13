# ADR-009 — Framework completion is independent of app delivery

Status: Accepted
Date: 2026-08-13
Decision owner: Pablo Alejo

ARTIFACT: architecture-decision
ARTIFACT: dependency-check
ARTIFACT: stream-validation

## Context

PRD-23 combined two different products of work:

1. the Copilot framework/content system—canonical `cc` transaction,
   conformance, entitlement, layered content, routing, evaluation, security,
   propagation, and fleet proof; and
2. the native Control Tower app—Swift invariants, crash-only supervision,
   publisher first trust, Apple signing/notarization, app publication,
   installation, and rollback.

The selected app first-trust design requires a separate Developer ID Installer
identity and attended exact-package ceremony. WP-832 proves that this machine
currently has the documented Developer ID Application identity and working
`ct-notary` profile, but no usable Installer identity. WP-834 proves that an
Application-signed artifact cannot satisfy the approved publisher first-trust
threat model. Neither finding says that `cc`, layered content, routing, or
framework installation fails.

The owner therefore directed that framework delivery proceed first and app work
be separated for later.

## Decision

- PRD-23/TASK-278 is the framework outcome program.
- PRD-24/TASK-301 is the owner-deferred app release and installation program.
- TASK-286, TASK-287, TASK-298, and TASK-289 move to PRD-24 with their task IDs,
  statuses, dependencies, metadata, and work products intact.
- TASK-302 provides the future independent app-candidate security gate.
- TASK-303 provides clean framework environment proof without an app artifact.
- TASK-291 remains mandatory but is framework-only integrated security before
  fleet mutation. It no longer depends on TASK-286 or TASK-287.
- TASK-288 uses the canonical `cc` path and no longer depends on TASK-298.
- TASK-290 depends on TASK-303 instead of TASK-289 and evaluates the provisioned
  framework outcome, not app installation.
- TASK-292 excludes app criteria and no longer depends on TASK-289 or TASK-298.

Dependency direction is one-way: deferred app validation may wait for exact
framework/content readiness, but no framework task waits for app completion.

## Active framework graph

```text
297 -> 296 -> 284 -> 285
  |                    \
  +-> 300               +-> 291 -> 288 -> 299 -> 303 -> 290 -> 292
       ^                      ^       ^
       |                      |       |
    281,295          exact content, census, evaluation
```

The existing detailed dependency table in `tc` remains authoritative. This
diagram shows only the remaining critical path.

## Deferred app graph

```text
286 -> 287 -> 302 -> 298 -> 289
                         ^      ^
                        297   framework readiness
```

## Alternatives rejected

- **Keep the combined graph.** Rejected because an Apple publisher-bootstrap
  credential would continue to block unrelated framework evaluation and fleet
  proof.
- **Weaken or bypass the app threat model.** Rejected because it converts a
  scheduling issue into a security regression and contradicts SOUL's
  say-only-what-you-can-prove rule.
- **Mark app tasks complete or cancel them.** Rejected because the candidate,
  publication, and app-install evidence does not exist; prior work and open
  gates remain valuable.
- **Remove clean-environment and human proof from framework acceptance.**
  Rejected because that would make the graph faster by weakening the product
  outcome rather than separating concerns.

## Consequences and failure modes

- PRD-23 can complete while PRD-24 remains deferred, but only after all
  framework/content/security/evaluation/fleet/human gates pass.
- PRD-24 cannot borrow PRD-23's security verdict for app signing, packaging, or
  installation. TASK-302 is mandatory before TASK-298.
- TASK-303 proves only framework operation in a clean environment. It cannot be
  cited as app installation, Gatekeeper, notarization, watchdog, or rollback
  evidence.
- TASK-290 may begin only after neutral provisioning is complete; observer help
  or mid-session provisioning invalidates the non-technical result.
- Cross-PRD dependencies are allowed only from the app track to framework
  readiness. A new reverse dependency is a regression.

## Fitness functions

- `orchestrate-validate.py` passes the seven-stream framework plan.
- `orchestrate-validate.py` passes the three-stream app plan.
- The `tc` dependency graph is acyclic.
- No PRD-23 pending/in-progress task depends directly or transitively on a
  PRD-24 task.
- TASK-291, TASK-288, TASK-299, TASK-300, and TASK-292 retain their framework
  security, census, mutation, post-fan-out, and provenance gates.

VERDICT: ACCEPTED — APP DELIVERY IS SEPARATE; FRAMEWORK GATES REMAIN INTACT.
