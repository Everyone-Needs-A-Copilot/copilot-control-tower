# Phase 3 — Security boundary and abuse-case plan

Date: 2026-08-12
Execution record: PRD-23, parent TASK-278
Security review task: TASK-291

## Security objective

The ecosystem must be safer than a person manually copying and updating executable-adjacent AI tooling across projects. It must carry authority and knowledge downward to entitled users while making personal-to-shared movement, secret inheritance, unproved provenance, destructive repair, and silent trust weakening impossible or fail-closed.

## Assets

- personal knowledge, preferences, memories, and work products;
- company and department confidential knowledge;
- GitHub identity, repository entitlement, and per-user push credentials;
- managed secret-store references and OS keychain material;
- signed manifests, release tags, source commits, and lock provenance;
- project-owned tracked, untracked, and staged work;
- executable-adjacent agents, skills, commands, hooks, and MCP configuration;
- Control Tower's compiled-in trust roots and signed update channel;
- evaluation prompts, outputs, source identities, and human-participant records;
- the credibility of every healthy, held, changed, or unchanged claim.

## Trust boundaries

| Boundary | Allowed crossing | Forbidden crossing |
| --- | --- | --- |
| Foundation → organization → department → personal | Pull-only inherited capability and knowledge according to entitlement and pins | Upward write authority or reverse synchronization on the unattended path |
| Personal device → shared repository | Separate, intentional, human-invoked authoring path with per-user credentials and review | Scheduled/background push, personal memory/content promotion, shared push credential |
| Git repository → materialized project | Signed/ref-verified, manifest-authorized content with lock and postcondition | Secret values, untrusted refs, symlink-escaped writes, content without source proof |
| `cc` → Control Tower | Versioned JSON facts and typed absence | Raw human CLI text as state, local recomputation, optimistic fallback |
| `copilot` operational services → solution workflow | Bounded service capability using credential references and least privilege | Ecosystem resolution, credential embedding in prompts or inherited files |
| Task/evaluation evidence → durable record | Sanitized plans, result metadata, hashes, bounded outputs approved for retention | Secrets, unrelated personal data, confidential content without explicit scope |
| Release source → installed app | Immutable pushed source, signed/notarized/stapled artifact, compiled-in roots | User-configurable feed/trust root, moved tag, unsigned replacement, bypass flag |

## Abuse cases and required controls

### AB-01 — Personal content is promoted into an organization or department repository

Exploit path: a shared authoring or fan-out command uses one tree/remote for every layer, or a content agent copies personal context into an organization extension.
Impact: irreversible privacy breach and loss of organizational trust.
Controls:

- separate source trees and remotes per layer;
- no shared push credential on personal/background paths;
- content authoring at the narrowest correct layer;
- deny/test personal markers and secrets in shared changes;
- independent source review before organization/department release;
- leak scan as a backstop, never the primary boundary.

Required proof: negative cross-tier write test, credential/path inspection, shared-content review artifact, fail-closed leak fixture.

### AB-02 — A secret value enters inherited content or evidence

Exploit path: token-bearing URL, PEM, API key, `.env` value, or command output is added to a repo, lock, test fixture, task WP, or model-evaluation artifact.
Impact: credential compromise across every entitled clone and history.
Controls:

- references only in manifests/content;
- fail-closed secret scanning before shared writes;
- sanitized fixtures and redacted command evidence;
- repository history review when a finding occurs;
- rotation treated separately from deletion.

Required proof: representative secret fixtures rejected, repository scans, WP/evaluation artifact checks, no secret values in logs.

Current triggered case: TASK-293 tracks removal and history/exposure assessment for personal/company tax identifiers and concrete financial figures found in shared accounting executable guidance. Department evaluation and release remain dependency-blocked until its security and QA gates pass.

### AB-03 — Lock attribution claims a source that did not materialize

Exploit path: resolver winner and lock writer use different item identities or destinations, allowing a declared personal/organization source to appear without matching disk content.
Impact: false provenance and unreviewed executable behavior.
Controls:

- canonical transaction owns materialization and lock generation;
- item identity includes source layer, immutable ref, content hash, and destination;
- postcondition compares lock and real disk state;
- E-4 remains S0 with paired failure fixtures.

Required proof: zero live E-4 failures, tampered lock/disk fixtures fail, clean/degraded round-trips converge.

### AB-04 — Materialization damages human-owned work

Exploit path: reset/rebase/delete/overwrite, symlink target escape, whole-file rewrite, or a “repair” action treats an authoring/project tree as disposable.
Impact: data loss, accidental push, and loss of confidence in unattended operation.
Controls:

- deterministic preflight before first irreversible write;
- explicit managed/disposable versus human-owned classification;
- dirty/customized/ambiguous states hold;
- no writes or deletes through escaping symlinks;
- completed-actions ledger on every exit;
- `HEAD == target` and disk postconditions.

Required proof: dirty tracked/untracked/staged fixtures, symlink escape fixture, interrupted-write case, empty-ledger requirement for “nothing changed.”

### AB-05 — An untrusted release or ref becomes executable-adjacent material

Exploit path: mutable branch, unsigned/mis-signed tag, wrong signer, tree missing the claimed path, moved tag, or user-configurable trust root.
Impact: supply-chain compromise.
Controls:

- compiled-in trust roots and signed inherited policy only;
- signed tag verification plus exact tree-path existence;
- immutable pins and ancestry/identity checks;
- no preference or flag can repoint trust;
- fail closed on missing security fields.

Required proof: bad signer, unsigned tag, missing path, mutable ref, missing field, and preference-override fixtures all fail.

### AB-06 — Entitlement is inferred rather than proved

Exploit path: cached repository presence or stale prior access is treated as current permission; layer content remains active after access is revoked.
Impact: unauthorized company/department knowledge remains in active use.
Controls:

- GitHub repository access remains authoritative;
- offline becomes honest unknown/holding, not assumed entitlement;
- revoke access plus rotate relevant managed-store tokens;
- document the accepted residual that already-downloaded content cannot be remotely wiped;
- urgent revocation does not introduce MDM or a destructive remote-delete channel.

Required proof: unentitled/revoked/offline fixtures produce distinct evidence-backed states; no false ready.

### AB-07 — Control Tower becomes a second resolver

Exploit path: Swift groups raw evidence into new health logic, verifies signatures locally, blends status, or uses last-known-good when the CLI is unreadable.
Impact: two sources of truth and false green.
Controls:

- exact-major schema gate per verb;
- render typed CLI verdicts only;
- unknown value and unreadable response fail closed;
- native source/behavior fitness checks;
- no raw internal token in visible or accessibility strings.

Required proof: malformed, missing-field, unknown-enum, exit-error, and offline fixtures never render healthy; native scan finds no resolver/signature/merge/wipe logic.

### AB-08 — Crash supervision becomes an unstoppable restart loop

Exploit path: launchd uses `KeepAlive=true`, cannot distinguish clean Quit from crash, or repeatedly resurrects a defective binary.
Impact: denial of service and inability for the user to stop the app.
Controls:

- `KeepAlive={SuccessfulExit:false}` only;
- one signed process, no daemon/fallback loop;
- clean Quit exits successfully;
- repeated-crash behavior and uninstall are tested;
- previous signed DMG is the rollback artifact.

Required proof: plist check, crash restart, clean Quit remains quit, uninstall removes supervision, rollback installs and launches.

### AB-09 — Optional integration failure rejects all solution work

Exploit path: notification, Discord, documentation cache, or other optional transport exits non-zero in a required hook path.
Impact: a peripheral outage disables every prompt or workflow.
Controls:

- optional transports fail open;
- security enforcement remains mandatory and separate;
- tests distinguish notification loss from protocol rejection.

Required proof: transport failure fixture leaves core protocol usable and records only the transport limitation.

### AB-10 — Behavioral evaluation leaks data or manufactures effectiveness

Exploit path: prompts include confidential or personal material beyond scope; model outputs are selectively retained; a synthetic marker or evaluator preference is reported as outcome proof.
Impact: privacy breach and false product claim.
Controls:

- versioned, sanitized realistic fixtures;
- foundation-only and layered controls;
- record runtime/model, content identity, rubric, and all evaluated artifacts;
- hard safety criteria separated from qualitative criteria;
- no unrelated participant data;
- structural and behavioral evidence remain distinct.

Required proof: artifact inventory, sanitization check, repeatable evaluation command, explicit rubric verdict and residual uncertainty.

### AB-11 — Parallel delivery changes the wrong repository or hides active work

Exploit path: overlapping agents edit the same files, fan-out touches active repos, or integration overwrites another agent's/user's changes.
Impact: lost work, unreviewable diffs, accidental broad mutation.
Controls:

- validated disjoint stream ownership;
- task and stream identity in every handoff;
- read-only status before mutation;
- no worktree creation/cleanup without current approval;
- cross-stream needs returned as contracts, not unauthorized edits.

Required proof: stream validator pass, task file metadata, clean conflict check scoped to PRD-23, per-stream diff and QA work product.

## Security gates by delivery phase

| Phase | Security gate |
| --- | --- |
| A — truthful installation | AB-03 through AB-06; no fleet mutation before transaction and lock review pass |
| B — real content | AB-01, AB-02, AB-10; no shared release before content security review |
| C — effectiveness | AB-02 and AB-10; no outcome claim without preserved controls and rubric |
| D — unattended delivery | AB-07 through AB-09; no application release before packaged-artifact security proof |
| E — fleet/human proof | AB-06, AB-10, AB-11; no completion claim before clean external evidence |

## Residual risks that must remain explicit

- Revoking repository access cannot remotely erase content already downloaded to a departed person's disk.
- Model-output evaluation is probabilistic; deterministic safety and materialization gates carry the hard release authority.
- Signing custody is not yet a staffed two-of-N model.
- A real human participant and second Mac are external resources; absence blocks the corresponding outcome claims rather than changing the criteria.
- Pure open source permits inspection but does not by itself prove a deployed binary matches reviewed source; signed provenance and packaged gates remain required.

## Independent review verdict contract

TASK-291 may approve only when every high-impact abuse case has a concrete implemented control and failable artifact. It must reject completion if personal/shared separation, source/lock truth, never-destroy behavior, compiled-in trust, or clean-Quit supervision is asserted only by prose.
