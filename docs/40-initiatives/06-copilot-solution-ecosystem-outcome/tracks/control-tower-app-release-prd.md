# Control Tower app release and installation PRD

Status: Owner-deferred; evidence preserved
Date split: 2026-08-13
Execution record: PRD-24, parent TASK-301

## Purpose

Finish the native Control Tower app's crash-only supervision, publisher
first-trust boundary, signed candidate, publication, clean installation, and
rollback proof when the owner resumes app work. This track is deliberately
separate from PRD-23: it may consume a completed framework, but it cannot block
framework correctness, content release, evaluation, security, or fleet closure.

## Preserved evidence

- TASK-286 remains **completed** with its existing implementation, QA, and
  security work products for native invariant enforcement and plain language.
- TASK-287 remains **in progress** with WP-815, WP-822, WP-824, WP-826,
  WP-828, WP-832, and WP-834. The source-only candidate boundary is approved;
  the independently trusted Installer-package first-use ceremony is not.
- TASK-298 remains **pending** and may publish only the exact candidate approved
  by TASK-302.
- TASK-289 remains **pending** and owns app installation, clean-Quit,
  crash-restart, clean-home/second-Mac, and rollback evidence.

No prior status, verdict, identity finding, commit, or work product was promoted
or discarded by the split.

## Requirements

1. The app renders versioned `cc` facts and never computes ecosystem truth.
2. Shipping native Swift invariant and plain-language gates remain green.
3. Crash-only supervision restarts after unsuccessful termination, clean Quit
   stays quit, and `KeepAlive` is never `true`.
4. Publisher first trust binds one immutable source/package tuple through an
   independent authority, root-owned staging, post-install verification, and a
   monotonic anti-downgrade ledger.
5. Publication uses immutable pushed source and an exact independently approved
   candidate; Developer ID signature, notarization, staple, installer receipt,
   provenance, and rollback links all verify.
6. Clean-home and cold-second-Mac app runs require no terminal repair, manual
   repository wiring, ad hoc resigning, or mutation of user work.

## Acceptance criteria

| ID | Criterion | Task |
| --- | --- | --- |
| APP-AC-01 | Native app invariants and plain-language rendering are enforced against shipping Swift. | TASK-286 |
| APP-AC-02 | Crash-only supervision and publisher first trust pass exact-candidate QA/security. | TASK-287, TASK-302 |
| APP-AC-03 | The exact approved app is published with signature, notarization, staple, provenance, and rollback proof. | TASK-298 |
| APP-AC-04 | The published app installs, supervises, and rolls back correctly in clean-home and cold-second-Mac cells. | TASK-289 |

## Dependency graph

```text
TASK-286 (completed) -> TASK-287 (in progress) -> TASK-302 -> TASK-298 -> TASK-289
                                                     ^          ^          ^
                                              app security   TASK-297   framework-ready
```

TASK-298 retains TASK-297 because the eventual app publication must be tested
against approved immutable framework/content inputs. TASK-289 retains its
framework-readiness dependencies. These are one-way dependencies from the app
track to the framework track; no PRD-23 task depends on app completion.

## Failure posture

The existing Developer ID Application identity and `ct-notary` profile can sign
and notarize application/DMG artifacts. They do not satisfy the separately
selected `productsign` Installer identity boundary. This distinction is an app
publisher-design issue, not evidence that the framework fails to install or run.
Do not weaken the first-trust threat model to make this deferred track green.
