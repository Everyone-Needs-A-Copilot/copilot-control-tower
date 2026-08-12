# Clean user-home and second-Mac validation protocol

Status: protocol only; not executed
Task: TASK-289
Acceptance criterion: [AC-18](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence)

## Purpose

Prove that the final signed ecosystem can be installed and used through the
ordinary user-facing journey in both a genuinely clean user home and a cold
second Mac. The run must not inherit Pablo's caches, checkouts, credentials,
materialized content, or untracked fixes. It must not use terminal repair,
manual repository wiring, or a substituted simulation.

This document authorizes no machine change. TASK-289 remains pending until an
authorized operator executes this protocol against the final artifacts and
stores the evidence.

## Entry gate

Do not schedule or begin either run until all of these facts are linked in the
TASK-289 execution work product:

- TASK-297 is complete: organization and accounting inputs are owner-approved,
  signed, immutable, pinned, and proven at the real consumer.
- TASK-298 is complete: the Control Tower artifact is published from immutable
  pushed source and its signature, notarization, staple, install verification,
  provenance, and prior signed rollback artifact are recorded.
- TASK-299 is complete: post-fan-out entitlement and personal/shared boundary
  security has no unexplained blocking result.
- TASK-285, TASK-287, and TASK-288 satisfy TASK-289's task dependencies.
- The operator has the exact release URL, artifact digest, application version
  and build, source commit/tree, layer refs/trees, signer identities, and prior
  signed rollback artifact. A mutable branch or moving download URL is not an
  identity.
- The device owner authorizes the test accounts, installation, evidence
  capture, rollback exercise, and later cleanup. No existing home or working
  directory will be deleted or reset to manufacture a clean state.
- Required GitHub entitlement and ordinary sign-in paths are available. Test
  credentials belong to the test actor and are entered only in the normal
  trusted sign-in surface; observers never receive or record them.

If any prerequisite is missing, record `NOT RUN — PREREQUISITE MISSING`, name
the responsible actor, and stop. Absence is not a product failure and cannot be
reported as a pass.

## Test environments

Run the same release through two distinct cells.

| Cell | Required state | What it proves |
| --- | --- | --- |
| Clean home | A newly created, dedicated standard macOS user on an eligible Mac, with no prior Copilot configuration, caches, repositories, materialized trees, application preferences, or credentials | The journey does not depend on the publisher's prepared home |
| Second Mac | A physically distinct eligible Mac that has not run this candidate; use a new dedicated standard user if the machine has any prior ecosystem state | The signed release and pinned layers travel to another machine without local author knowledge |

Record macOS version, hardware architecture, whether the device is managed,
network class, and cell ID. Do not record device serial number, local username,
home path, IP address, Wi-Fi name, personal Apple ID, or unrelated installed
software.

Before the observed journey, a verifier may check the downloaded artifact on
a separate verification machine. Once the journey begins, the test device may
use only the published artifact, ordinary instructions, macOS, GitHub's normal
sign-in surface, and the shipped user-facing product.

## Evidence manifest

Create one content-addressed manifest per cell. Record:

- session ID and cell (`clean-home` or `second-mac`);
- artifact URL, digest, version/build, source commit/tree, signature authority,
  notarization/staple/Gatekeeper verdicts, and rollback artifact identity;
- immutable organization/department refs, trees, signer/policy identities, and
  final consumer lock/content identities;
- start/end timestamp, each visible product state, and every user action;
- screenshots of relevant user-facing states with secrets, account handles,
  local paths, repository names, notifications, and unrelated applications
  cropped or redacted;
- completed-actions ledger and postconditions, including explicit zero-change
  evidence for a blocked path;
- result for each acceptance row below, with artifact links;
- every diagnostic action, even when it occurs only after the run has stopped.

Never store credentials, cookies, tokens, recovery codes, private keys, local
usernames, home paths, personal repository names, client content, or full Git
remotes. Use stable pseudonymous device/session IDs. Run value-suppressing
sensitive-content checks before attaching evidence to `tc` or Git.

## Run procedure

Execute every step in both cells. Do not carry state from the first cell into
the second.

1. Start from the documented clean state. Capture only the allowed state
   declaration; do not seed configuration, copy a cache, clone an ecosystem
   repository, or preinstall a private layer.
2. Download the exact TASK-298 artifact through the ordinary published path.
   If the bytes do not match the recorded digest, stop.
3. Install and launch using only the ordinary user-facing instructions. Do not
   open Terminal, a Git client, a repository host's advanced settings, or a
   hidden support tool.
4. Follow the first-run journey exactly as presented. The actor may approve
   macOS prompts and complete their own GitHub sign-in. The observer does not
   interpret an internal term or tell the actor which button to choose.
5. Confirm that setup reaches an honest user-facing terminal state. A success
   state must be backed by the shipped CLI/lock/ledger contract; an unavailable
   check must remain visibly unknown rather than green.
6. Open one new synthetic project through the documented product path and
   confirm that the expected Claude and Codex foundation plus entitled shared
   contributions are present with matching lock/content identities. Do not
   manually copy, symlink, clone, edit a manifest, or repair a lock.
7. Exercise the ordinary cadence or `Sync now` surface once. Confirm the result
   through the product's visible state and completed-actions ledger.
8. Quit normally and verify it remains quit. Launch again and verify the
   previously proved state is re-derived rather than assumed.
9. Perform the documented rollback using the exact prior signed artifact. A
   rollback operator may follow the published user-facing rollback procedure;
   no source build, ad hoc resigning, moving tag, manual repository reset, or
   deletion of user work is allowed. Verify signature, launch, and preserved
   user/project state after rollback.
10. End the cell and seal its evidence before beginning the other cell.

## No-repair rule

Opening Terminal, editing configuration, cloning or resetting a repository,
copying files from another home, clearing product state, changing a lock,
re-signing an artifact, or asking Pablo to intervene ends the observed run.
Record the last proved state and `FAILED — REPAIR REQUIRED`. Diagnostics may
begin only after that record is sealed; diagnostics cannot convert the run to
a pass. A fixed build requires a new artifact identity and a complete new run
in both cells.

## Acceptance rubric

Each row is `PASS`, `FAIL`, or `NOT PROVED`. Both cells must pass every hard
row; there is no average.

| Required result | Hard gate |
| --- | --- |
| Exact signed, notarized, stapled artifact matches immutable TASK-298 provenance | Yes |
| Ordinary install and first run complete without terminal, Git, manual repository wiring, Pablo intervention, or copied state | Yes |
| Entitled Claude and Codex content resolves/materializes with exact released source and lock identity | Yes |
| Unentitled, unavailable, or offline state is honest and actor-correct; no false green | Yes |
| Personal/unrelated content is neither read, copied, changed, nor exposed | Yes |
| `Sync now`/cadence produces a truthful completed-actions ledger and verified postcondition | Yes |
| Clean Quit remains quit; later launch rechecks state | Yes |
| Prior signed rollback installs and launches without deleting or rewriting user work | Yes |
| The second-Mac result distinguishes environment/entitlement failure from a product defect with evidence | Yes |

AC-18 may be marked demonstrated only when both cell manifests exist, all hard
rows pass, independent QA validates the artifacts, and no security finding is
open. One clean home on the publisher's Mac is not second-Mac proof.

## Stop conditions and disposition

Stop immediately on artifact identity mismatch, signature/notarization/staple
failure, unexpected privilege request, secret or personal-data exposure,
symlink/path escape, dirty/customized work mutation, false success state,
terminal/Git repair requirement, missing completed-actions evidence, rollback
that threatens user work, or any unexplained TASK-299 boundary deviation.

Preserve a redacted failure artifact, identify the responsible actor, and
return the defect to the owning task. Do not retry in place. If the second Mac
is unavailable, record `NOT RUN — EXTERNAL RESOURCE UNAVAILABLE`; AC-18 stays
pending.

## Claim boundary

Passing this protocol supports only the bounded AC-18 statement that the
recorded signed release completed the documented journey in the two recorded
environments. It does not prove fleet-wide reliability, general availability,
behavioral effectiveness, or non-technical-person success.
