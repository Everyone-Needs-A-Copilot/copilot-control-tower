# Phase 0 — Goal-to-current-state gap analysis

Date: 2026-08-12
Evidence baseline: Initiative 05 post-handoff audit, handoff documents, live source, and the 2026-08-12 `cc conformance` runs recorded there.

## Executive conclusion

The ecosystem has a credible technical skeleton but does not yet deliver the approved outcome.

It can discover and resolve layers, install substantial foundation content, keep durable task state, expose operational capabilities, supervise the CLI, and detect many kinds of drift. The conformance harness is a major advance because it can fail honestly.

The remaining distance is not one bug. It is a chain of gaps between four states:

1. **Available:** a capability exists somewhere in the ecosystem.
2. **Installed:** the expected files and contracts reach a project.
3. **Wired:** the runtime actually consumes the resolved result.
4. **Effective:** the inherited knowledge and specialist methods measurably improve what a person creates.

Today, foundation content is mostly available, installed, and wired. Organization and department content are mostly absent. The full installer is split. Some lock evidence disagrees with real materialization. Effectiveness is proved only with synthetic markers, not real company work. The non-technical journey is designed but not validated.

## Target state

An ordinary person starts with a real problem. The ecosystem determines their entitlement, resolves the correct foundation, organization, department, and personal contributions, installs them into Claude and Codex, assembles the right specialist workflow, gives that workflow controlled operational tools, preserves its decisions and evidence, and helps produce a secure, maintainable solution. Control Tower keeps the tooling dependable without becoming a second resolver. The resulting project stays self-contained and owned by its creators.

## Gap summary

| ID | Target capability | Current evidence | Gap | Consequence | Exit proof |
| --- | --- | --- | --- | --- | --- |
| G-01 | One complete install transaction | `/setup-project`, `cc workspace`, and the Codex installer materialize different subsets. Explicit round-trip is 17 pass / 1 S0 fail. | No single owner defines the complete Claude + Codex result. | “Installed” depends on which entry point ran; project parity cannot be guaranteed. | Both user-facing setup surfaces delegate to one transaction; clean and degraded round-trips produce the same reference lock and files. |
| G-02 | Lock truth matches disk truth | Three S0 `resolve_attribution_matches_lock` failures remain for personal-tier Knowledge, CLI, and Codex plugin attribution. | Personal plugin winners are not recorded/materialized the way 55 passing subjects are. | The ecosystem can claim a source that the real install cannot prove. | Zero E-4 S0 failures without weakening the check; negative fixture still fails. |
| G-03 | “Full” means complete | Ordinary `--full` runs zero round-trip checks; explicit round-trip exposes an additional S0. | The operator command omits its highest-value destructive-sandbox proof. | A user can run the documented complete check and miss a blocking failure. | `cc conformance check --full` includes round-trip; help, schema, docs, and tests agree. |
| G-04 | Regression truth reflects reviewed intent | Baseline comparison reports 82 PASS→FAIL and 16 new failures; `expected_today` still expects fixed root causes to fail. | Intentional exclusions, new checks, and regressions are not reconciled. | CI can be green while live regression evidence is unactionable. | Every delta is classified; real regressions fixed; reviewed baseline regenerated with rationale; zero unreviewed regressions. |
| G-05 | Conformance findings are actionable | Global exclusion failures repeat 76 times; authoring trees are mistaken for mirror violations; unreachable results mix deliberate exclusions with real scanner gaps; nine could-not-run results remain. | Scope, exception, and environment semantics are incomplete. | Noise hides the small set of conditions an operator must act on. | Global checks emit once; accepted authoring/exclusion states carry evidence; genuine failures stay red; no unexplained unknowns. |
| G-06 | Organization knowledge changes execution | No real organization-tier command or agent wins attribution. The stale org `protocol.md` was correctly deleted. | The organization layer contains little executable guidance that affects specialist behavior. | Output remains generic even when the mechanism resolves correctly. | At least one substantive organization contribution in each relevant execution surface wins, materializes, and changes controlled output. |
| G-07 | Department expertise changes execution | No accounting-department command or agent wins attribution. | Department practices exist as repositories but do not reach solution workflows as executable guidance. | Accounting work cannot reliably receive department-specific methods and controls. | Real accounting contributions win, materialize, and improve department-relevant controlled cases. |
| G-08 | Specialist philosophy is complete | No `uids.extension.md` or `cco.extension.md` exists at any tier. | Visual and creative specialists have no tier-specific direction to inherit. | These specialists behave like generic roles and cannot express organization taste. | Substantive, scoped extensions exist, resolve through the real loader, and have positive and fallback tests. |
| G-09 | Effectiveness is behaviorally demonstrated | E-1 uses a synthetic organization marker; no with/without evaluation of real agent output exists. | Structural conformance is being used as a proxy for solution quality. | The program cannot answer whether the ecosystem helps people create better, company-specific solutions. | Versioned evaluation cases compare foundation-only and layered runs against observable outcome criteria; results are reproducible and evidence-bound. |
| G-10 | Claude and Codex are two faces of one system | Both receive framework material, but installer parity and real organization/department attribution are not proven end to end. | Runtime differences can become intent differences. | A person can receive materially different organizational help depending on the execution environment. | Shared intent has runtime-specific adapters, parity fixtures, and no unexplained capability gap. |
| G-11 | Shared improvement propagates without Pablo | Fan-out exists, but the content supply is sparse and current baseline/exclusion state needs manual interpretation. | Updating the right layer does not yet produce a self-evident, verified downstream outcome. | Pablo remains the practical integration and interpretation layer. | A shared content change is released, pulled, materialized, behaviorally verified, and reported without manual per-project wiring. |
| G-12 | Personal leverage preserves privacy and authority | Strong doctrine and many structural controls exist; the three personal lock mismatches remain and no end-to-end negative behavioral leak suite proves personal data cannot move upward. | The most sensitive layer has incomplete proof. | A privacy failure would invalidate organizational trust. | Cross-tier write paths are structurally absent; leak fixtures fail closed; locks prove source; credentials remain references only. |
| G-13 | Control Tower enforces its shipping invariants | Native Swift ships, but the 40 fitness tests scan retired Rust and CI is disabled; the crash-only watchdog is not implemented; the SOUL records a live jargon leak. | The app's quality bar is stated more strongly than it is mechanically enforced. | A thin renderer can regress into a false or technical surface without a failing gate. | Native invariant suite runs in CI, jargon cannot reach visible/a11y strings, crash-only supervision works with `KeepAlive={SuccessfulExit:false}`, and the packaged signed artifact passes. |
| G-14 | The real target user can succeed | No non-technical person has completed the journey; no second machine has cold-started. | Persona and reliability claims remain hypotheses. | The system may work only for its author in a prepared environment. | Clean-machine proof plus observed non-technical journey, with no terminal, no raw Git, no false claims, and only owner-appropriate prompts. |
| G-15 | The proof record survives sessions | Initiative 05 cites a PRD/tasks missing from the referenced live DB; docs contain stale counts and merge status. | Source commits are durable, but execution provenance is fragmented. | Future agents cannot confidently distinguish history from current truth. | Initiative, PRD, tasks, work products, commits, QA verdicts, and releases cross-link and validate. |
| G-16 | Fleet state supports the outcome | 235 failures and nine unknowns remained in the recorded ordinary full run; many are duplicate or ratified exceptions, others are real per-repo drift. | The fleet has not been reduced to a reviewed set of actionable deviations. | “Works everywhere it should” cannot be claimed. | Every result is fixed or dispositioned; no S0; no unexplained unknown; exceptions are explicit, non-duplicated, and auditable. |

## What already works and must be preserved

- The four-layer resolver has deterministic precedence and equal-rank protection.
- The distinction between installed, wired, and effective is now explicit in code.
- The harness uses severity rather than a misleading health percentage.
- Negative fixtures prove that important checks can fail.
- Root-cause checks RC-1 through RC-5 pass live.
- Content-level staleness replaced the version-only false-green gate.
- Tag and tree verification fail closed.
- Dirty human-owned trees and symlink escapes are treated as safety boundaries.
- `cc` owns ecosystem state; `copilot` owns operational services.
- Task Copilot preserves plans, evidence, and handoffs.
- Control Tower's shipping architecture is native Swift and already renders CLI contracts through an explicit boundary.

## Gap dependencies

```text
G-01 canonical install ─┬─> G-02 lock truth ─┬─> G-06/G-07 real layered content
                        │                    └─> G-10 runtime parity
                        └─> G-03 full proof ─────> G-04/G-05 actionable conformance

G-06/G-07/G-08 content ─────> G-09 behavioral effectiveness ─────> G-11 propagation proof

G-02 + G-09 ────────────────> G-12 privacy proof

G-01 + G-03 + G-12 ─────────> G-13 trustworthy supervision ──────> G-14 real-user proof

all technical/content streams ────────────────────────────────────> G-16 fleet closure
all evidence streams ─────────────────────────────────────────────> G-15 durable provenance
```

## Priorities

### P0 — truth and safety blockers

- G-01 canonical install transaction
- G-02 lock/materialization S0 failures
- G-03 complete full-mode proof
- G-12 personal isolation and credential boundaries

### P1 — outcome blockers

- G-06 organization contributions
- G-07 department contributions
- G-08 specialist extensions
- G-09 behavioral effectiveness
- G-10 Claude/Codex parity

### P2 — operational trust and reach

- G-04 regression baseline
- G-05 actionable conformance semantics
- G-11 propagation without Pablo
- G-13 native Control Tower enforcement and watchdog
- G-16 fleet remediation

### P3 — adoption proof and record integrity

- G-14 clean-machine and non-technical-person validation
- G-15 durable provenance

Priority expresses dependency and consequence, not permission to leave later outcomes incomplete.

## Completion interpretation

Passing code tests is necessary but insufficient. Passing structural conformance is necessary but insufficient. The initiative succeeds only when a real nearer-tier contribution is entitled, resolved, installed, consumed, observable in the resulting solution behavior, safely kept within its boundary, and deliverable to a non-technical person without Pablo manually connecting the system.
