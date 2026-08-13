# Phase 1 — Copilot Solution Ecosystem outcome PRD

Status: Active
Date: 2026-08-12
Product owner: Pablo Alejo
Delivery owner: Codex
Execution record: PRD-23, parent TASK-278, delivery TASK-279 through TASK-300
Source target: [Initiative 05 goal-driven audit](../../05-ecosystem-conformance-audit/retrospectives/2026-08-12-work-audit.md)

Current evidence snapshot: [2026-08-12 progress and acceptance-evidence review](../retrospectives/2026-08-12-progress-evidence-review.md). The initiative remains active. Owner decisions and several release mutations have occurred, but no final outcome claim is permitted while runtime and publisher-anchor security remain open, provider-side accounting purge and human reviews are incomplete, hosted CI is in maintenance mode, and evaluation/fleet/external validation are absent.

## 1. Product requirement

Build and prove a Copilot Solution Ecosystem that gives an ordinary person the practical capabilities of a trustworthy, company-aware, multidisciplinary solution team.

The person begins with a problem rather than infrastructure. Their GitHub entitlement selects the organization, department, and personal layers they may receive. `cc` resolves and installs the applicable Claude, Codex, CLI, and Knowledge material. The protocol assembles the appropriate specialists. `copilot` supplies bounded operational capabilities. `tc` preserves execution evidence. Control Tower keeps the tooling working and reports only CLI-proven truth. The resulting solution remains self-contained and belongs to its creators.

## 2. Problem statement

The ecosystem can install substantial foundation material and has a sophisticated conformance harness, but the user outcome is not yet demonstrated:

- project installation has multiple owners and inconsistent results;
- three S0 attribution claims do not match materialized lock evidence;
- the command described as a full check omits round-trip verification;
- baseline and exception semantics obscure actionable truth;
- no real organization or department agent/command contribution currently wins;
- visual and creative specialist extensions are absent;
- no controlled evaluation shows inherited content causing attributable, company-specific process, context, decision, or artifact differences;
- Control Tower's native invariants and crash recovery remain unimplemented gaps;
- the journey has not been proved on a clean second machine or with a non-technical person.

The product risk is a technically impressive installation system that reliably delivers generic assistance.

## 3. Users and jobs

### Primary: a non-technical solution creator

When I have a real problem, I want the system to bring me the right expertise and tools without making me assemble or maintain them, so I can create a useful solution and still own the result.

### Enabler: an organization operator

When I improve company or department guidance, I want the correct people and projects to receive it safely and verifiably, so the organization becomes more capable without a manual rollout.

### Author: a trained knowledge or method contributor

When I add reusable expertise to an allowed shared layer, I want it validated, released, inherited, and behaviorally checked without risking personal or unrelated content.

### Trust owner: Pablo

When the ecosystem changes, I want evidence that it is correct and effective without having to connect each repository, interpret noisy failures, or personally sustain the sync layer.

## 4. Product principles and non-negotiable constraints

1. **Say only what can be proved.** Missing evidence becomes unknown or held, never healthy.
2. **`cc` owns ecosystem truth.** Control Tower and other surfaces parse its versioned JSON contracts; they do not re-resolve state.
3. **Plain words at the human boundary.** Internal tier, severity, manifest, rank, and Git vocabulary cannot reach user-facing or accessibility strings.
4. **Personal cannot move upward.** Separate trees, remotes, credentials, and write capabilities make the leak impossible by construction.
5. **Never destroy human-owned work.** Dirty working trees, authoring trees, and symlink escapes fail safely.
6. **Claude and Codex share intent, not necessarily implementation details.** Runtime adapters may differ; organizational purpose, specialist model, knowledge, safety posture, and observable outcome may not drift without an explicit exception.
7. **Projects remain self-contained.** The ecosystem distributes the tools used to build solutions, not the solutions themselves.
8. **As little app as possible.** One signed Control Tower binary, no model surface, no second scheduler, no bypass mode, no `KeepAlive=true`.

## 5. Scope

### In scope

- canonical project-install transaction and adapter migration;
- complete Claude + Codex materialization and lock provenance;
- conformance full-mode, round-trip, baseline, exception, scope, and unknown-result correctness;
- real ENAC organization and accounting-department contributions;
- `uids` and `cco` extension content at the appropriate tiers;
- a behavior-level effectiveness evaluation system;
- Claude/Codex parity evidence;
- personal-boundary security verification;
- native Swift invariant checks, plain-language boundary, and crash-only watchdog;
- fleet remediation and reviewed exceptions;
- clean-home/cold-machine and non-technical journey validation;
- documentation, PRD/task state, QA, security, and release provenance.

### Out of scope

- MDM, forced configuration, fleet monitoring, telemetry, analytics, or a hosted service;
- Windows and retired Tauri/Rust implementation work;
- Control Tower chat, local health computation, or a second ecosystem resolver;
- project/product synchronization;
- secret values in Git or inherited material;
- a paid or closed-source tier;
- real-time sync;
- automatic upward publishing or revival of deferred `repair`/`publish` without a new ADR;
- claiming general availability before the external validation gates pass.

## 6. Functional requirements

### FR-1 — Entitlement and resolution

- GitHub repository access remains the entitlement spine.
- `cc` resolves foundation → organization → department → personal for Claude, Codex, CLI, and Knowledge.
- Entitled, unentitled, offline, stale-entitlement, and revoked states are explicit, fail closed at protected layers, and provide an actor-correct recovery path.
- Nearer intentional overrides win; additive dimensions combine; empty placeholders cannot shadow substantive content.
- Every winning executable item reports source layer, immutable source reference, content identity, and materialized destination. CLI and Knowledge sources may instead be consumed through a versioned runtime adapter, but that consumer path and source identity must be recorded.

### FR-2 — Canonical project transaction

- One library-level transaction owns the complete reference install.
- `/setup-project`, `cc workspace`, and Codex setup become adapters over that transaction rather than independent installers.
- The transaction preflights before mutation, preserves project-owned content, records a completed-actions ledger, installs all expected Claude agents and commands, installs the Codex plugin/skills, writes one canonical lock, and asserts postconditions.
- A degraded eligible install is repaired; a dirty or ambiguous human-owned state is held without destructive action.

### FR-3 — Conformance truth

- Ordinary full mode includes all designed layers, including sandboxed round-trip.
- Live, fixture, and baseline truth are separately labeled but reconcile through explicit reviewed decisions.
- Global checks emit once.
- Ratified exclusions carry structured path, reason, authority, and review evidence.
- Authoring checkouts are distinguished from managed mirrors without weakening real mirror checks.
- Could-not-run results identify the missing prerequisite and owning actor.

### FR-4 — Real layered content

- Organization content expresses stable ENAC purpose, operating principles, solution-creation expectations, terminology, security posture, and shared methods.
- Accounting content expresses department-specific practices, controls, evidence expectations, and review boundaries.
- Content is assigned to the narrowest correct layer and does not duplicate foundation material.
- Claude and Codex receive runtime-appropriate representations of the same intent.
- Knowledge supplies source material and reusable skills; executable surfaces point to it rather than copying large bodies of prose.

### FR-5 — Specialist extensions

- `uids` receives organization-specific visual direction without replacing its foundation craft.
- `cco` receives organization-specific creative direction without inventing brand facts.
- Extensions use the current loader contract, contain substantive guidance, and have explicit fallback behavior.

### FR-6 — Behavioral effectiveness

- Evaluation cases begin with realistic problems, not ecosystem vocabulary.
- Each case has foundation-only and layered variants using controlled inputs.
- Observable criteria measure attributable company context, department method use, human-centered framing, traceability, safety, and maintainability signals. They do not support a generalized claim that the ecosystem produces better solutions.
- Evaluations distinguish deterministic materialization checks from model-output judgments.
- Model-output results record runtime/model, prompt fixture, resolved content identity, evaluator rubric, and artifacts.
- No single aggregate percentage can hide a hard safety failure.

### FR-7 — Task and operational integration

- Protocol routing selects the right specialist sequence based on the problem.
- `copilot` capabilities remain operational-service tools and never become an ecosystem resolver.
- `tc` records plans, decisions, implementation, QA, security, handoffs, and artifacts across sessions.
- Optional transports fail open and cannot reject every prompt.

### FR-8 — Control Tower trust

- Control Tower renders versioned `cc` JSON and does not compute ecosystem state.
- Native Swift invariant checks replace retired-tree fitness claims and run unconditionally in CI.
- Visible and accessibility strings use plain layer labels and closed state mappings.
- Crash-only launchd supervision restarts only after unsuccessful termination; clean Quit remains quit; `KeepAlive` is never `true`.
- Packaged, signed behavior—not source-only mocks—passes the release gate.

### FR-9 — Propagation and fleet closure

- A reviewed change at organization or department level can be released once and reach every entitled, eligible project on the normal cadence or `Sync now`.
- Fan-out does not touch excluded, dirty, unentitled, or ambiguous projects.
- Every live conformance failure is fixed or has a structured reviewed disposition.
- Exceptions do not repeat per repository when the condition is global.

### FR-10 — Human validation

- A clean user home or second Mac completes installation from the signed artifact.
- A non-technical person can begin a representative problem, use the resulting specialist workflow, and understand every prompt without terminal, Git, manifest, rank, or raw severity knowledge.
- The system asks them only about their sign-in or their own material.
- Pablo does not manually repair, copy, or connect repositories during the journey.

## 7. Non-functional requirements

### Security and privacy

- No secret values in inherited content, logs, fixtures, task work products, or repositories.
- Signed tag/tree and lock verification fail closed.
- Personal-layer paths hold no shared push credential.
- Negative tests cover cross-tier write, secret-bearing URL, symlink escape, untrusted ref, missing security field, and stale lock cases.
- Security posture cannot be weakened through user preferences or flags.

### Reliability

- Idempotent clean install and update.
- Deterministic reference output for the same pinned layers and project policy.
- Explicit offline, unreadable, held, and partial-progress states.
- Postconditions compare real disk state and lock evidence, not command stdout.

### Maintainability

- One implementation per authoritative decision.
- Runtime adapters are thin and tested against shared fixtures.
- Check registries have completeness and positive/negative fixture tests.
- Documentation links to live commands and versioned schemas.

### Accessibility and language

- Status is never color-only.
- Keyboard, focus, labels, and VoiceOver semantics are tested where UI changes.
- No internal tokens appear in visible copy, tooltips, notifications, or accessibility labels.

### Performance

- Fast mode remains appropriate for routine supervision.
- Full mode may take longer but must be complete and explicit about sandboxed mutation.
- Control Tower uses one coalesced cadence and manual `Sync now`, not real-time polling.

## 8. Acceptance criteria and current evidence

Status terms are evidence states, not percentages: **accepted stream gate** means the producing task has independent approval but final integrated closure may remain; **partial** means some required evidence exists; **rejected gate** means the latest applicable QA/security verdict blocks the criterion; **owner-gated** means preparation exists but no authorization or mutation is claimed.

| AC | Criterion and required evidence | Current evidence state | Remaining gate |
| --- | --- | --- | --- |
| AC-01 | One canonical transaction produces the complete Claude + Codex reference install; clean/degraded round trips, identical lock, adapter proof. | **Accepted stream gate.** TASK-279 and signed tier-provenant Codex consumer TASK-294 are completed with QA/security approval. | Re-run in final integrated QA against released tier refs. |
| AC-02 | Ordinary full conformance includes round-trip; CLI/help/schema and real full-result proof. | **Accepted stream gate.** TASK-280 is completed with QA approval. | Confirm in final integrated live run. |
| AC-03 | No S0 conformance failure remains; live zero-S0 JSON and negative fixtures. | **Partial.** Transaction/conformance fixes and current baseline work are approved in TASK-279/280/281. | Final live fleet result after release and approved fan-out in TASK-288/292. |
| AC-04 | No unexplained could-not-run result remains; every unknown has prerequisite and actor. | **Partial.** Actionable unknown semantics are approved in TASK-280/281. | Final fleet-wide live verification in TASK-288/292. |
| AC-05 | Regression truth is reviewed and current; classified deltas and regenerated baseline. | **Accepted stream gate.** TASK-281 is completed with QA approval. | Revalidate after remaining integrated changes. |
| AC-06 | Conformance output is actionable; deduplication, structured exclusions, authoring/mirror distinction. | **Accepted stream gate.** TASK-280 is completed with QA approval. | Final integrated conformance run. |
| AC-07 | Real organization content wins and materializes with source, lock, and content identity. | **Partial.** TASK-282 content and TASK-294 signed consumer mechanics are approved; the exact organization tree is a signed candidate behind required review. | Human review, tag, pin, entitled consumer proof, and evaluation. |
| AC-08 | Real accounting content wins and materializes for a department case. | **Partial.** The approved accounting tree is a signed sanitized root with `v1.0.0`, protections, pin, and bounded current-byte proof. Signed PR #65's entitlement-bound runtime snapshot lifecycle has QA/security approval through WP-782. | Merge the approved runtime seam after maintenance, complete provider garbage collection, prove an exact entitlement-qualified live read, and run EVAL-05. |
| AC-09 | `uids` and `cco` extensions resolve with substantive loader and fallback proof. | **Partial.** Organization extension inputs are approved through TASK-282. | Immutable release and consumer identity in TASK-297; final integrated loader proof. |
| AC-10 | Layered content changes relevant behavior in controlled Claude/Codex comparisons. | **Pending.** Phase 4 and WP-718 define the contract; no behavioral effectiveness result is claimed. | TASK-284 then TASK-285 after TASK-296/297. |
| AC-11 | Foundation controls do not regress. | **Pending.** WP-718 defines criterion-wise non-regression without a generalized score; outcome evidence does not exist. | Implement and run foundation controls in TASK-284/285. |
| AC-12 | Personal content cannot leak upward; negative security and path/credential proof. | **Partial.** Transaction/content security gates and accounting current-tree containment are approved. | Behavioral leak cases and integrated pre/post-publication security in TASK-284/291/299. |
| AC-13 | One shared change propagates to multiple eligible projects without manual copies. | **Preparation approved; execution pending.** WP-728 approves a deterministic 75-row census with zero mutation authority. | Refresh after TASK-297, independently re-review, obtain owner approval, then TASK-288 fan-out proof. |
| AC-14 | Native Control Tower invariants run against shipping Swift. | **Accepted stream gate.** TASK-286 is completed with QA/security approval. | Preserve the gate through candidate and release verification. |
| AC-15 | Crash-only supervision is correct in the packaged release. | **Security/runtime gate.** WP-808 selects a script-free signed payload package. WP-812 implements the package/receipt/verifier boundary and source QA WP-813 approves it, but security WP-814 rejects the first-trust handoff. Architecture WP-815 concludes that a fully automated first install is impossible under the hostile-same-user/no-preinstalled-helper model: owner intent and freshness must enter through an independent signing context and an attended exact-package approval. No Developer ID Installer identity or approved package tuple exists. | Provision the independent Installer identity; owner-approve the immutable source, monotonic version, app identity/digests, and signed-package digest; install that exact package from root-owned staging; atomically advance a protected version-floor ledger only after installed-state verification; repeat QA/security and then build the candidate. |
| AC-16 | Control Tower uses plain language with source/rendering/a11y proof. | **Accepted stream gate.** TASK-286 is completed with QA/security approval. | Verify packaged candidate and final release do not regress it. |
| AC-17 | Fleet is dispositioned with zero S0/unknown and reviewed residuals. | **Preparation approved; execution pending.** WP-728 approves the bounded provisional census contract and zero-authority state. | Refresh after TASK-297, obtain immutable review and owner approval, then execute TASK-288 and integrated QA. |
| AC-18 | Clean-machine journey succeeds from a signed artifact with rollback proof. | **Pending.** No final signed artifact exists. | TASK-287/291/297/298/288/299, then TASK-289. |
| AC-19 | A non-technical person succeeds without terminal or Pablo intervention. | **Pending.** No observed journey is claimed. | TASK-289 then TASK-290. |
| AC-20 | Initiative, PRD, tasks, WPs, commits, QA/security, and releases cross-link. | **Partial.** Task/WP evidence now includes owner decisions, public/archive repository identities, signed roots/tags, protected PRs, maintenance state, and this matrix. | Reviewed merges, final tags/releases, restored hosted checks, and TASK-292 validator. |
| AC-21 | Entitlement lifecycle is safe and actor-correct across entitled/unentitled/offline/stale/revoked/reauthorized states. | **Accepted stream gate.** TASK-295 is complete; WP-708 is approved by security WP-713 and QA gate WPs 714/715. | Preserve the contract through integrated pre/post-release review. |
| AC-22 | Protocol, specialists, operational capabilities, and Task Copilot form one durable problem-to-solution journey. | **Pending.** WP-706 defines the structural fixture and WP-718 defines the dependent evaluation architecture; neither claims implementation or outcome. | Implement TASK-296 after TASK-297, then TASK-284/285. |
| AC-23 | Shared organization/accounting inputs are owner-approved, signed, pinned, and proven at the consumer. | **Active gate.** Owner decisions are recorded. Accounting has a signed root/tag and protections; organization remains a signed review candidate; signed runtime PR #65 has QA/security approval through WP-782. | GitHub Support purge, organization review/tag/pin, PR #65 merge after maintenance, need-to-have access confirmation, and exact entitled consumer proof. |

## 9. Delivery phases

### Phase A — Truthful installation and conformance

Close G-01 through G-05 and G-12's lock boundary. Produce the canonical transaction, fix personal attribution, include round-trip in full mode, reconcile baseline semantics, and reduce noisy/unknown results.

### Phase B — Real organizational capability

Close G-06 through G-08 and G-10's content side. Author organization and accounting contributions, add `uids`/`cco` extensions, and prove real resolution/materialization in Claude and Codex.

### Phase C — Behavioral effectiveness

Close G-09 and prove the effective state. Build versioned evaluation cases, control foundation-only versus layered runs, preserve artifacts, and define hard safety gates.

### Phase D — Trustworthy unattended delivery

Close G-11 through G-13. Prove propagation, port shipping invariant checks to native Swift, close the plain-language leak, implement crash-only supervision, and release Control Tower from immutable pushed source.

### Phase E — Fleet and human proof

Close G-14 through G-16. Remediate or disposition the fleet, validate a clean environment and second machine, run the non-technical-person journey, and close the provenance chain.

## 10. Parallel streams and file ownership

Streams execute only when dependencies are complete. Write scopes are deliberately disjoint.

| Stream | Specialist route | Owns | Depends on | Delivers |
| --- | --- | --- | --- | --- |
| Stream-A Canonical Transaction | `$ta → $me → $qa → $sec` | `claude-copilot/tools/cc/src/cc/core/ecosystem/**`, setup/update adapter commands, focused non-conformance tests | none | AC-01, AC-03 lock fix, AC-12 transaction safety |
| Stream-B Conformance Truth | `$me → $qa` | `claude-copilot/tools/cc/src/cc/core/conformance/**`, conformance command, conformance tests/docs | none | AC-02 through AC-06 |
| Stream-C Layered Content | `$doc → $qa → $sec → owner approval → $do` | ENAC organization and accounting tier repositories only | none | AC-07 through AC-09 and AC-23 content inputs |
| Stream-D Outcome Evaluation | `$ta → $me → $qa` | protocol/capability continuity integration, new evaluation modules/fixtures, and evaluation result artifacts | A, B, C | AC-10, AC-11, AC-22, behavior side of AC-12 |
| Stream-E Control Tower Trust | `$ta → $me/$uid → $qa → $sec → $do` | shipping `native/**`, native invariant tests, packaging/watchdog assets, app contract docs | A, B | AC-14 through AC-16 |
| Stream-F Fleet Closure | `$do → $me → $qa` | an approved explicit eligible-project census and per-repository integration files; never content-authoring trees or the global exception schema | A, B, C, D, pre-release security, published app | AC-13, AC-17 |
| Stream-G External Validation | `$sd → $uxd → $qa → $doc` | validation protocol, fresh-home/second-machine artifacts, observed journey records | D, E, F | AC-18, AC-19 |
| Stream-Z Integration and Release | `$qa → $sec → $do → $doc` | integration evidence, task/provenance links, final release and retrospective | all | AC-20 and final verdict |

No stream may edit another stream's owned files. Cross-stream changes are handed back to the owning stream as a failing test or work product.

## 11. Task graph

1. Establish PRD, gap baseline, streams, tasks, and ownership.
2. In parallel: canonical transaction; conformance truth; layered content.
3. Integrate A/B/C and prove structural resolution/materialization.
4. Build and run outcome evaluation.
5. In parallel after the CLI contract settles: Control Tower trust work and fleet closure.
6. Build and verify a signed release candidate, then run pre-publication security and integrated QA; return defects to owning streams.
7. Publish the approved Control Tower and signed tier-content releases, then run the explicitly approved fleet fan-out through the real cadence/Sync Now consumer.
8. Run post-fan-out security verification, clean-machine validation, and non-technical-person validation.
9. Re-run full conformance, baseline, evaluation, initiative, security, and provenance gates.
10. Publish the final outcome retrospective only if all acceptance criteria have evidence.

## 12. Architecture decisions

### ADR-P1 — Canonical transaction lives in `cc`

Decision: the complete project transaction is a library-level `cc` capability. Shell commands and Codex scripts become thin adapters.
Rejected: keeping multiple installers “in sync” with duplicate logic; defining correctness in Control Tower.
Consequence: migration must preserve existing entry points while eliminating independent behavior.

### ADR-P2 — Effectiveness evidence has structural and behavioral halves

Decision: deterministic tests prove entitlement, resolution, materialization, locks, and prompt assembly; controlled evaluations assess resulting model behavior. Neither substitutes for the other.
Rejected: claiming effectiveness from synthetic file markers; making stochastic output a release-blocking byte comparison.
Consequence: behavioral evidence records context and rubric, while hard safety requirements remain deterministic gates.

### ADR-P3 — Content belongs at the narrowest stable layer

Decision: foundation holds universal craft, organization holds durable ENAC intent, department holds accounting practice, personal holds Pablo-specific preference/private context.
Rejected: copying foundation into nearer layers; putting personal voice or memory into organization content.
Consequence: shared content is smaller, easier to audit, and less likely to shadow improvements.

### ADR-P4 — Exceptions are evidence, not silence

Decision: reviewed exclusions use structured metadata and emit one attributable result.
Rejected: requiring empty registries; duplicating one global condition across every repo; treating exclusions as invisible.
Consequence: the report stays honest without making intentional policy look like 76 independent defects.

### ADR-P5 — Control Tower remains a witness

Decision: new status or recovery behavior requires a versioned CLI fact. Native fitness checks constrain rendering and invocation boundaries, not ecosystem resolution.
Rejected: implementing missing CLI state in Swift for convenience.
Consequence: some UI work must wait for upstream JSON contracts.

## 13. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Canonicalization breaks an established installer path. | Characterization fixtures for every current path, adapter migration, clean/degraded/dirty states, and rollback. |
| Content is invented or too generic. | Cite existing ratified company material, keep claims narrow, run owner review and behavioral cases, never invent policy. |
| Organization content leaks personal preferences. | Narrowest-layer review, path/remotes audit, secret and personal-marker scans, independent security verdict. |
| Model variability makes evaluations flaky. | Separate deterministic gates, version prompts/rubrics, use multiple cases, record runtime/model, judge bounded criteria rather than exact prose. |
| Conformance is weakened to make the report green. | Preserve negative fixtures, require evidence for expectation changes, and independent QA review check diffs. |
| Parallel agents collide. | Validated file ownership, no worktrees without separate approval, disjoint scopes, and owner-routed integration. |
| Fleet fan-out touches active work. | Read-only preflight, exclusion/dirty gates, per-repo ledger, no reset/rebase/delete/push of human work. |
| Application work creates release obligations. | Treat signed/notarized/stapled publication as part of the task, not a follow-up. |
| External human or second-machine evidence is unavailable. | Complete all automatable gates, preserve an executable protocol, and keep the initiative active rather than fabricating completion. |

## 14. Verification strategy

- Focused unit/property tests for resolver, transaction, lock, scope, exception, and native invariant behavior.
- Integration tests against real temporary Git repositories and isolated user homes.
- Round-trip tests for clean, degraded, customized, dirty, offline, unentitled, and malformed states.
- Conformance negative fixtures that prove each S0/S1 check still fails when violated.
- Security abuse cases for secret insertion, cross-tier write, symlink escape, untrusted ref, preference override, and clean-Quit watchdog behavior.
- Behavioral evaluation cases with foundation-only, organization, department, and personal variants.
- Claude/Codex parity matrix describing supported runtime differences.
- Packaged artifact tests for any Control Tower change.
- Real clean-machine and observed-user evidence for final closure.

## 15. Release and rollback

- CLI/content repositories use immutable commits and signed release references where their current contracts require them.
- No tag is moved. A bad release is superseded.
- Fleet rollout begins with isolated fixtures, then representative pilot projects, then eligible fan-out.
- Control Tower application changes increment the appropriate version and end in a signed, notarized, stapled, verified release built from immutable pushed source.
- Every release record names the prior signed artifact and exact rollback procedure.

## 16. Definition of done

“Done” is not a green unit-test run, a populated 16-layer manifest, or a clean install on Pablo's prepared Mac.

Done means a real company and department contribution reaches an entitled person's Claude and Codex environments through one trustworthy transaction, changes relevant solution behavior in the intended direction, preserves personal privacy and project ownership, stays working under Control Tower without false claims, propagates without Pablo manually wiring projects, and succeeds for a non-technical person on a clean machine. Every part of that sentence must have a durable artifact.
