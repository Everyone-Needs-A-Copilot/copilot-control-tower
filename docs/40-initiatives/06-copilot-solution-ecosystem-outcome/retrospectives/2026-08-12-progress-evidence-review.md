# Initiative 06 progress and acceptance-evidence review

Updated: 2026-08-13

Execution record: PRD-23, parent TASK-278

Evidence window: current task graph and work products through WP-817

Disposition: **Active; outcome not yet achieved**

## Plain-language answer

The ecosystem foundation is substantially stronger and several high-risk boundaries are now implemented, independently tested, and preserved in durable evidence. The program is not complete because the two active release tasks still have open security, provider, and human-review gates, and the behavioral, fleet, publication, clean-machine, and observed-person phases have not started.

What changed materially:

- The canonical Claude/Codex transaction, conformance truth, signed plugin materialization, native rendering boundary, and entitlement lifecycle are completed stream gates.
- The approved accounting source was rewritten to a signed sanitized history root and released as `v1.0.0`. Observable refs and authorized local mirrors are clean. GitHub still serves the old unreachable object by direct SHA, so provider garbage collection remains required.
- Control Tower now has a clean public source repository with one new history root. The former repository is preserved as a private archived repository; old releases, issues, Actions artifacts, and Git history were not migrated.
- The repository-contained Control Tower launcher was rejected as a circular trust anchor. A separately signed, notarized, stapled publisher anchor was installed and passed QA, but security rejected `/Applications` as writable by the logged-in administrator. Architecture WP-808 selects a script-free signed installer package. WP-812 implements the local package/receipt/verifier contract and source QA WP-813 approves it, but security WP-814 rejects the first-trust handoff because mutable checkout code still gains signing authority and the Installer input is not bound to the exact approved package and source. Architecture WP-815 confirms that a fully automated first install is impossible under this threat model without an existing independent trust anchor; the first secure install must therefore be owner-attended and bind one exact package and source tuple out of band. No app candidate exists.
- GitHub Actions are temporarily disabled on all 55 organization repositories to stop repeated runs while defects are fixed locally. Branch protections, review rules, signer rules, and tag protections remain enabled. Actions must be restored from the WP-785 ledger with full-SHA pinning and clean hosted verification before merge or release.
- The formerly red `claude-copilot` workflow failures have local fixes, but the current PR heads are not yet fully covered by the earlier bounded verdicts. PR #63 is at `c61ff0c`; PR #65 is at remote head `617cef6` with additional local follow-up. The WP-780/WP-782 Knowledge runtime approvals bind only to `a7cc08d`. Branch convergence, exact-head QA/security, full-SHA pinning, and hosted verification therefore remain required after the owner-directed GitHub pause ends.

## Program snapshot

| State | Tasks | Meaning |
| --- | --- | --- |
| Completed with accepted bounded evidence | TASK-279, 280, 281, 282, 283, 286, 293, 294, 295 | Nine foundational transaction, conformance, content-input, native-trust, containment, signed-source, and entitlement tasks are complete. |
| Active | TASK-287, 297 | Control Tower candidate production and signed shared-content release remain blocked by explicit security, provider, or human-review gates. |
| Pending downstream | TASK-284, 285, 288-292, 296, 298-300 | Evaluation, integration, publication, fleet work, external validation, and final audit remain dependency-gated. |
| Parent | TASK-278 active | No final ecosystem outcome or release claim is authorized. |

## Current active gates

### Control Tower public source and release candidate — TASK-287

- Owner decisions are recorded in WP-747 and WP-751.
- The original repository is now `Everyone-Needs-A-Copilot/copilot-control-tower-private-archive-20260812`, private and archived at `fd1694f`.
- The canonical `Everyone-Needs-A-Copilot/copilot-control-tower` repository is public with one clean root commit. It excludes private initiatives, agent state, retired stacks, historical releases, private topology, and the old Git/GitHub record. Apache-2.0 is the selected license.
- QA WP-771 approved the public transition and source bootstrap at the reviewed revision. Security WP-772 rejected the repository-contained launcher because a local build and adjacent manifest could authenticate themselves.
- Architecture WP-773 moved release authority to an independently installed publisher anchor. The corrected anchor was Apple-accepted, stapled, installed, and approved by QA WP-789.
- Security WP-791 rejected that installed anchor because `/Applications` is writable by the logged-in administrator, allowing replacement before the genuine anchor can verify itself.
- Architecture WP-792 and implementation WP-793 moved the first executable to a root-only protected subtree. Independent QA WP-797 rejected the migration because it moved an attacker-replaceable old entry into the protected directory without validating or sanitizing it.
- Superseding implementation WP-799 installs only the freshly verified artifact into the protected directory. The rejected entry may only be renamed to a hidden, non-application quarantine path within `/Applications`; its bytes are never read, copied, trusted, executed, or imported into a trust root. Collision, rollback, symlink, ownership, writable-mode, ACL, invalid-identity, and replacement cases pass locally.
- QA WP-800 approved WP-799's exact generated install and rollback behavior. Security WP-801 rejected three additional pre-trust paths: `PYTHONPATH` startup execution before immutable verification, caller-controlled `TMPDIR` interpolation into the privileged shell, and a quarantine destination symlink race that could redirect rejected bytes into a protected directory.
- WP-802/WP-803 run pre-authority verification under an empty, isolated environment; send privileged inputs only as positional arguments; use root-created staging with root-side signature, Gatekeeper, and staple checks; and remove only the exact rejected path rather than moving it. The future ceremony intentionally does not restore the rejected old bytes.
- QA WP-804 approved the exact local source revision after four repeated security-focused runs. Security WP-805 rejected it because authority-bearing build and post-install verification still ran from a user-writable materialization; the root copy was not bound to an exact digest/CDHash, Team ID, and bundle ID; and destination/approval ancestors were not fully revalidated before mutation.
- WP-806 attempted a root-owned authenticated snapshot and exact candidate identity binding. QA WP-807 rejected it because the snapshot creator and its expected hash came from the same user-writable scratch path; its read-only fixture was still owner-writable after `chmod`; Team/bundle negatives did not exercise actual candidate-carried identity; approval-path zero-write coverage and the runbook were incomplete.
- Architecture WP-808 replaces repository-generated privileged shell with a payload-only Developer ID Installer package containing the root-only anchor and protected approval ledger. The package has no scripts; macOS Installer validates the package signature and performs privileged placement. The rejected `/Applications` bundle is removed only after successful installed-state verification and is never migration input or rollback.
- WP-812 completes the script-free payload package builder, versioned approval receipt, compiled bootstrap compatibility, hostile package/candidate mutations, source movement checks, and production verifier ancestry matrix. Source QA WP-813 approves the exact local revision.
- Security WP-814 rejects WP-812. The authenticated Git materialization never becomes the authority-bearing process: mutable checkout code continues into credentials, signing, notarization, and package signing. Separately, the verified package remains replaceable through a user-owned parent before Installer consumes it, while installed-state verification lacks an independently supplied expected package digest and source identity. This permits valid older same-team package substitution or downgrade.
- Architecture WP-815 closes the design question. A fully automated first install is not achievable while a hostile same-user process may alter all user-owned code and files and no protected helper or policy already exists. The feasible ceremony must independently approve the immutable remote/ref/commit/tree, monotonic package version, application CDHash and bundle digest, and final signed-package SHA-256; copy that package into root-owned non-writable staging; have Installer consume that exact path; verify the installed receipt/version and identities; and only then advance a separate non-overwritable root policy/version-floor ledger. Signatures, notarization, package receipts, a disk image, or the admin prompt do not by themselves prove owner intent or freshness.
- The machine has a Developer ID Application identity but no independently provisioned Developer ID Installer identity. The owner has not yet approved an exact out-of-band package/source tuple. These are now explicit first-install prerequisites, not implementation details that repository automation can safely manufacture.
- WP-812 remains local and unpushed under the organization-wide GitHub pause. The older `/Applications` anchor remains rejected.
- **Current result:** public source exists, but no security-approved protected publisher anchor is installed, no Control Tower candidate has been built, and nothing has been published.

### Shared organization and accounting content — TASK-297

- Owner approval for the exact trees, history purge, protections, and compiled signer is recorded in WP-747/WP-748.
- Accounting `main` is signed root `493cec9`, tree `1c27ea0`, with signed immutable tag `v1.0.0`. Branch and `v*` tag protections are active. The current scanner, source checkout, authorized mirror, manifest pin, and current consumer bytes pass bounded checks.
- GitHub still resolves the legacy sensitive commit by direct SHA even though no branch, tag, PR, or fork references it. WP-753 contains the value-suppressed GitHub Support request for cached-view removal and server-side garbage collection. Until GitHub confirms removal, `historyPurged=false` and external copies remain uncontained.
- Organization content is a signed exact-tree candidate in protected PR #1. It remains `REVIEW_REQUIRED`; organization `main`, tag, and pin are unchanged.
- Accounting scanner enforcement and tag immutability were implemented after security WP-755. The current Accounting PR check was green before maintenance mode; the earlier failure email came from a deliberately failing synthetic PR that was closed and removed from the active workflow.
- Protected per-read Knowledge provenance is on signed PR #65. WP-780 approves its exact signed revision and security WP-782 approves the entitlement-bound snapshot lifecycle, closing the stale-path retention blocker.
- **Current result:** the accounting current release slice and bounded runtime security control are real, but TASK-297 cannot complete until PR #65 is merged after maintenance, organization human review/tag/pin, GitHub Support garbage collection, the named need-to-have access review, and an exact entitlement-qualified live read close.

### `claude-copilot` release trust — PR #63

- PR #63 is open, review-required, and blocked at current head `c61ff0c`. Its hosted failures are stale results from the short-lived workflow restore window, not current local proof.
- The local release-trust fixes and the overlapping PR #65 Knowledge-runtime work still require one dependency-ordered branch convergence, complete local framework suites, and exact-head QA/security before either PR may advance.
- The content defects that generated repeated workflow emails were fixed at their source: Knowledge iteration, three context-budget overruns, and dead skill references.
- Hosted checks are intentionally paused while Actions maintenance is active. The PR remains `REVIEW_REQUIRED` and unmerged; stale hosted failures must not be used as either approval or rejection of the converged head.

### GitHub Actions maintenance

- WP-785 supersedes the smaller maintenance boundary: Actions are disabled on all 55 `Everyone-Needs-A-Copilot` repositories, with zero queued or running jobs and an exact repository-by-repository restore ledger.
- WP-760 records the restore order: enable Actions only after owner authorization, restore full-SHA pinning, reverify required check/app bindings and protections, then trigger only explicitly authorized verification runs.
- Maintenance mode is temporary. A release or initiative-completion claim is forbidden while Actions remain disabled.

### Fleet census and evaluation

- WP-728 approves only the bounded preparation contract: a deterministic 75-row census with zero mutation authority. It must be refreshed and independently re-reviewed after TASK-297.
- WP-706 and WP-718 are architecture-only contracts for TASK-296 and TASK-284. No protocol-integration or behavioral-effectiveness result is claimed.
- Clean-machine and nontechnical-participant protocols exist, but neither has been executed.

## Acceptance evidence matrix

| AC | State | Evidence held now | What remains |
| --- | --- | --- | --- |
| AC-01 | Accepted stream gate | TASK-279/294 QA and security | Final integrated run against released refs |
| AC-02 | Accepted stream gate | TASK-280 QA | Final integrated full run |
| AC-03 | Partial | Approved transaction/conformance/baseline work | Final live zero-S0 fleet result |
| AC-04 | Partial | Actionable unknown semantics | Final fleet-wide live verification |
| AC-05 | Accepted stream gate | TASK-281 QA | Revalidate after integration |
| AC-06 | Accepted stream gate | TASK-280 QA | Final integrated conformance |
| AC-07 | Partial | Approved organization inputs and signed consumer mechanics | Organization review, tag, pin, and real consumer proof |
| AC-08 | Partial | Signed sanitized accounting release; protected runtime QA/security approval | Provider GC, exact entitlement-qualified live proof, and EVAL-05 |
| AC-09 | Partial | Approved `uids`/`cco` extension inputs | Organization release and integrated loader proof |
| AC-10 | Pending | Phase 4 and WP-718 architecture | TASK-284/285 controlled behavior artifacts |
| AC-11 | Pending | Criterion-wise foundation-control contract | Implement and run controls |
| AC-12 | Partial | Multiple transaction/content security gates | Behavioral leak cases and integrated security |
| AC-13 | Preparation approved, execution pending | WP-728 zero-authority 75-row census | Refresh after TASK-297, owner approval, and fan-out proof |
| AC-14 | Accepted stream gate | TASK-286 QA/security | Preserve through packaged release |
| AC-15 | Security/runtime gate | WP-808/815 architecture, WP-812 implementation, source QA WP-813, security WP-814 | Provision an independent Installer signing identity and owner-approve the exact package/source tuple; implement the root-staged monotonic ceremony; fresh QA/security; attended install and installed-state review; then candidate |
| AC-16 | Accepted stream gate | TASK-286 QA/security | Packaged candidate regression check |
| AC-17 | Preparation approved, execution pending | WP-728 deterministic provisional census | Immutable approved census and TASK-288 execution |
| AC-18 | Pending | Validation protocol only | Signed artifact and second-machine execution |
| AC-19 | Pending | Participant protocol only | Observed nontechnical-person journey |
| AC-20 | Partial | Durable tasks, WPs, commits, PRs, and this matrix | Merges, tags, releases, final validator |
| AC-21 | Accepted stream gate | TASK-295 QA/security | Preserve through integrated pre/post-release review |
| AC-22 | Pending | WP-706/WP-718 architecture | TASK-296 implementation and behavioral evidence |
| AC-23 | Active gate | Owner approval, signed accounting root/tag, protections, signed organization candidate, runtime QA/security approval | Provider GC, organization review/tag/pin, exact entitled proof, access confirmation |

The full criterion wording remains in the [PRD acceptance matrix](../phases/phase-1-outcome-prd.md#8-acceptance-criteria-and-current-evidence).

## What each remaining task will do

| Task and plain-language purpose | Current prerequisite or constraint | Concrete evidence required for completion |
| --- | --- | --- |
| **TASK-278: This task is to deliver the complete Copilot Solution Ecosystem outcome program.** | Every child task must finish, and TASK-292 must independently approve the integrated result. | All 23 acceptance criteria accepted; final QA metadata approved; initiative, PRD, tasks, work products, commits, reviews, releases, fleet records, and validation evidence linked in the final retrospective. |
| **TASK-284: This task is to build the behavioral-effectiveness evaluation contract and its realistic test fixtures.** | Waits for TASK-296's accepted journey adapter and TASK-297's immutable content identities. Architecture WP-718 is a design contract, not an implementation result. | Versioned cases, foundation-only and layered controls, observable rubrics, runtime and content identity capture, hard safety gates, negative fixtures, and independent QA/security approval. |
| **TASK-285: This task is to run the controlled Claude and Codex effectiveness evaluations and preserve what happened.** | Waits for TASK-284 and TASK-296. It may not turn model judgments into an unsupported aggregate claim. | Every attempt and resolved identity preserved; criterion-level foundation/layered comparisons for supported runtimes; hard safety-gate results; parity-gap dispositions; and evidence that the foundation control did not regress. |
| **TASK-287: This task is to finish crash-only supervision and produce a verified Control Tower release candidate without publishing it.** | Requires an independently controlled Developer ID Installer identity, owner approval of one exact source/package tuple through a trusted outside channel, root-owned staging, a monotonic anti-downgrade ledger, and an attended first-install ceremony. WP-814's security rejection remains open. | Immutable pushed source; exact package/source binding; valid same-team substitution, downgrade, and race tests; clean-Quit and crash-restart proof; signed, notarized, stapled candidate; installed receipt and identity verification; fresh QA and security approval. |
| **TASK-288: This task is to remediate or formally disposition each eligible repository in the approved fleet.** | Waits for behavioral evidence, integrated security, the published Control Tower release, and owner approval of TASK-300's exact census. Only the approved rows may be changed. | A per-repository execution ledger showing the intended normal-cadence or Sync Now operation, preserved active work, and explicit skips for every dirty, unentitled, excluded, or ambiguous repository. |
| **TASK-289: This task is to prove the signed ecosystem journey in a fresh user home and on a cold second Mac.** | Waits for the final signed release, fleet operation, and post-fan-out security verification. Access to the actual second machine is real external evidence an agent cannot manufacture. | Signed-artifact identity, fresh-home and second-machine transcripts, preserved rollback artifact, and proof that the journey needed no terminal repair or manual repository wiring. |
| **TASK-290: This task is to validate the complete journey with a consenting non-technical person.** | Waits for TASK-289 and the post-fan-out security result. A simulated agent session cannot substitute for a real participant's understanding. | An observed journey record against the task rubric, comprehension and actor-appropriate prompt findings, privacy-safe notes, and proof that the participant needed neither terminal work nor Pablo's intervention. |
| **TASK-291: This task is to perform the independent integrated security review before publication or fleet mutation.** | Waits for the exact TASK-287 candidate, TASK-297 immutable content and pins, TASK-285/TASK-296 evidence, and the approved TASK-300 census. Findings return to the stream that owns the affected files. | Independent review bound to the exact candidate, content releases, signer policy, entitlement behavior, locks, watchdog, evaluation artifacts, and census; no unresolved secrets, symlink, cross-tier, downgrade, or project-ownership finding. |
| **TASK-292: This task is to run the final integrated QA, provenance, release, and outcome audit.** | Runs last, after publication, fleet work, post-fan-out security, second-machine proof, and the non-technical-person journey. | A 23-for-23 acceptance audit with exact work-product, commit, QA/security, signed-release, rollback, fleet, and human-validation links; final retrospective; approved parent QA status. |
| **TASK-296: This task is to prove that one real problem moves through protocol routing, the right specialists, operational capabilities, and Task Copilot continuity.** | Waits for TASK-297's immutable content releases. Architecture WP-706 defines the adapter and evidence shape but does not prove the journey. | QA/security-approved JourneyAdapter and JourneyEvidence artifacts showing attributable organization/department context, optional transports failing open, mandatory security failing closed, and task state surviving a resumed session. |
| **TASK-297: This task is to approve and publish the organization and accounting content as signed, immutable inputs.** | Requires dependency-ordered PR #63/#65 convergence, exact-head QA/security, independent content PR reviews, GitHub Support purge/GC confirmation, final need-to-have roster confirmation, and narrowly restored hosted checks. Existing WP-780/WP-782 approval is bounded to `a7cc08d`, not the current PR #65 head. | Reviewed merges; new nonmoving signed tags; exact manifest pins and signer-policy proof; provider confirmation that the legacy object no longer resolves; approved least-privilege roster; and exact entitlement-qualified consumer identities. |
| **TASK-298: This task is to publish only the security-approved Control Tower candidate.** | Waits for TASK-287, TASK-291, and TASK-297. Source completion or a same-team signature alone is not publication authority. | Public release points to the exact approved candidate and immutable source; Developer ID signature, notarization, staple, installer, provenance, rollback, and release-link verification all pass. |
| **TASK-299: This task is to independently check entitlement and ownership boundaries after fleet fan-out.** | Runs immediately after TASK-288 and must stop final closure on any unexplained deviation. | Real per-repository checks showing no cross-entitlement, personal-to-shared, secret, symlink, lock, or project-ownership breach, with every deviation explained and resolved. |
| **TASK-300: This task is to create and obtain owner approval for the exact fleet census that TASK-288 may act on.** | Waits for TASK-297, then must regenerate the provisional 75-row snapshot. WP-728 grants zero mutation authority, and blanket permission cannot approve a future unknown row set. | Deterministic current census with entitlement, dirty state, exclusion, actor, exact intended operation and target for every repository; independent QA; immutable census identity; explicit owner approval of that exact set. |

The completion evidence above is a gate, not a forecast. A task remains unfinished until its named artifacts and independent decisions exist.

## Dependency-safe path forward

1. Preserve PR #65's QA/security approval and the local full-SHA corrections while the organization-wide GitHub pause remains active.
2. Provision the Developer ID Installer identity in an independently controlled signing context and prepare the immutable package/source tuple required by WP-815; do not attempt another self-authorizing repository bootstrap.
3. Obtain owner approval for that exact tuple, implement and review root-owned staging plus the monotonic version-floor ledger, then repeat source QA/security.
4. When the owner ends the pause, push/review the approved source and pending Action-SHA commits without enabling workflows prematurely; while the owner is present, run the attended exact-package install and obtain installed-state QA/security before building the Control Tower candidate.
5. Submit WP-753 through GitHub Support and verify the legacy accounting object no longer resolves.
6. Complete organization review, signed tag, immutable pin, need-to-have roster confirmation, and exact entitled consumer proof.
7. Complete TASK-296, then TASK-284/285 and TASK-291 before any Control Tower publication.
8. Restore Actions/security settings exactly as recorded in WP-760/785 only after the owner declares the work complete; prove active PR checks green without rerun noise.
9. Publish only through TASK-298 after pre-publication security, then refresh/approve the fleet census and run TASK-288/299.
10. Run TASK-289 and TASK-290 against final signed artifacts, then close with TASK-292 only if all 23 criteria pass.

## Claim boundary

It is accurate to say that the core transaction, conformance, entitlement, signed accounting root, public-source transition, and several native/runtime security controls are real and evidence-backed. It is not accurate to say the ecosystem is complete, fully purged, fully reviewed, released, fleet-propagated, behaviorally effective, clean-machine proven, or validated with a nontechnical person.

This report records current evidence. It does not approve a PR, restore Actions, merge or tag content, install the publisher anchor, publish a Control Tower release, authorize fleet mutation, or close the initiative.
