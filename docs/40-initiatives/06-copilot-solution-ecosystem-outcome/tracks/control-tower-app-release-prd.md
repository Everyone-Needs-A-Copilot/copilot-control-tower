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

## Security boundaries and abuse cases

The app track owns the assets and boundaries removed from PRD-23: Control
Tower's compiled trust roots and signed update channel, the versioned `cc` fact
boundary rendered by Swift, and the immutable release-source-to-installed-app
chain. TASK-302 reviews the exact candidate independently; it cannot borrow a
framework verdict from TASK-291.

### APP-AB-01 — Control Tower becomes a second resolver

Exploit path: Swift groups raw evidence into new health logic, verifies
signatures locally, blends status, or uses last-known-good when the CLI is
unreadable.

Controls and proof:

- exact-major schema gate per verb;
- render typed CLI verdicts only;
- unknown values and unreadable responses fail closed;
- native source/behavior fitness checks;
- no raw internal token in visible or accessibility strings; and
- malformed, missing-field, unknown-enum, exit-error, and offline fixtures
  never render healthy, while the native scan finds no resolver, signature,
  merge, or wipe logic.

### APP-AB-02 — Crash supervision becomes an unstoppable restart loop

Exploit path: launchd uses `KeepAlive=true`, cannot distinguish clean Quit from
a crash, or repeatedly resurrects a defective binary.

Controls and proof:

- `KeepAlive={SuccessfulExit:false}` only;
- one signed process with no daemon or fallback loop;
- clean Quit exits successfully;
- repeated-crash behavior and uninstall are tested; and
- plist inspection, crash restart, clean-Quit persistence, uninstall, and
  rollback installation/launch evidence all pass against the installed app.

### APP-AB-03 — A valid but unapproved package wins first trust

Exploit path: mutable checkout code, user-writable staging, same-team package
substitution, or downgrade causes Installer to consume bytes other than the
owner-approved immutable source/package tuple.

Controls and proof:

- independent approval binds source ref, commit/tree, monotonic version,
  application identity/digests, and final signed-package SHA-256;
- Installer consumes the exact package from root-owned non-writable staging;
- installed receipt, version, identities, notarization, staple, and package
  digest are verified before the protected anti-downgrade ledger advances; and
- substitution, downgrade, writable-ancestry, symlink, ownership, race, and
  rollback fixtures fail closed against the exact candidate.

### TASK-302 independent verdict contract

TASK-302 may approve only when APP-AB-01 through APP-AB-03 have concrete,
implemented, failable evidence against one exact immutable app candidate. It
must reject if compiled app trust, typed rendering, publisher first trust,
package/source identity, clean Quit, crash restart, signature, notarization,
staple, receipt, anti-downgrade, or rollback safety is asserted only by prose.
TASK-302 approval is required before TASK-298 publication. Installed clean-home
and cold-second-Mac execution remains a separate mandatory TASK-289/APP-AC-04
gate after publication; its absence cannot block PRD-23.

Residual app risks remain explicit: a real second Mac is an external resource,
and open source alone cannot prove that a deployed binary matches reviewed
source. Missing second-Mac evidence keeps APP-AC-04 pending, while exact signed
provenance and packaged-candidate gates remain required for APP-AC-02/03.

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
