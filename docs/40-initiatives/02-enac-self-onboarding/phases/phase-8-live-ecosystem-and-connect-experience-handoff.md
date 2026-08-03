# Phase 8 — Live ecosystem, the Connect experience, and the open fronts

Status: **Ecosystem live at 16/16 on this Mac; five releases shipped this arc; the one open live-state gap is a server-side Infisical credential rejection awaiting the owner's dashboard re-mint.**

Date: 2026-08-03

Owner: Pablo Alejo

Parent PRD: `tc prd 15`, "Phase 7 — Honest ecosystem setup transaction (ENAC gap closure)"

This document supersedes [`phase-7-transaction-fix-and-owner-runbook.md`](phase-7-transaction-fix-and-owner-runbook.md) as the current pickup. Open a new session against this file, not phase-7 or phase-6 — this is the file `docs/START-HERE.md` now points at.

App repository: `copilot-control-tower`, branch `app-build`

Helper repository: `claude-copilot`, branch `feat/adopt-and-project-setup`

Work is recorded across `tc` tasks 214–222 and work products WP-354 through WP-410 (`tc wp list --task 222 --json`, `tc wp list --task 220 --json`, `tc wp list --task 221 --json` cover the bulk of it).

## Purpose

Phase 7 closed all 13 gaps PRD 15 named and left an owner runbook for the live apply and the release. This document records what actually happened next: the live apply completed, five releases shipped, the protocol-inheritance and personal-voice work landed, the Connect-experience/self-service-provisioning design chain ran to a ratified ADR, and the app got a visual-truthfulness pass. Every claim below was checked against this machine's live state on 2026-08-03 — `git log`, `gh release list`, the manifest file, a read-only `cc onboard` plan, and `cc connections --json` — not transcribed from memory or from the WPs' own self-reports. Where a claim could not be independently re-verified, that is stated explicitly rather than presented as checked.

---

## 1. Where we are now (verified)

**The ecosystem is live at 16/16 on this machine.** `/Users/pabs/.config/copilot/copilot.layers.yml` has exactly 16 layer entries and every one carries a populated `source.path` (confirmed by parsing the file directly). A read-only `cc onboard --org Everyone-Needs-A-Copilot --json`, run from `/tmp` — never from inside `claude-copilot` itself, see §5 — against the installed signed helper (`/Applications/Copilot Control Tower.app/Contents/Resources/cc`, version 2.3.0) returns all 16 `layers` rows as `action: reuse` / `sync_state: current`, zero rows in `review`. The top-level `result` still reads `changes-required` because the `layer-manifest` stage itself wants a metadata-only repair to record the currently-resolved pins — not because any repository needs work.

**Five releases shipped this arc**, verified via `gh release list --repo Everyone-Needs-A-Copilot/copilot-control-tower`:

| Version | Date | Headline |
|---|---|---|
| v0.3.0 | 2026-08-01 13:11 | Honest setup transaction — the preflighted-saga/ledger/schema-2.0 work from ADR-006/007 first shipped |
| v0.3.1 | 2026-08-01 13:58 | Snapshot-pin classifier fix (the ninth closed history-classification state, ADR-006 addendum) |
| v0.3.2 | 2026-08-01 18:31 | Never-destroy guard, live-verified — the fix that followed the 2026-07-27 P0 org-content destruction (below) |
| v0.4.0 | 2026-08-02 13:49 | The connections bridge — `cc connections --json` and the wizard step 6 / Settings render of it |
| v0.5.0 | 2026-08-03 14:03 | Visual refresh + Connect sheet — the P1 native design-system pass and the in-app secret-input Connect sheet |

**The `cc` helper chain ran 2.0.0 → 2.3.0 this arc** (confirmed: `claude-copilot/tools/cc/pyproject.toml` reads `2.3.0`, and `git log --oneline` on `feat/adopt-and-project-setup` shows the full chain). Headline fixes, in order: **2.0.0** broke the onboard schema to v2.0 per ADR-007; **2.0.1** peeled annotated-tag `FETCH_HEAD` to its commit SHA; **2.0.2** added the ninth classifier state for parentless snapshot pins; **2.0.3** closed the never-destroy guard's symlink/clean-repo-with-remote holes — this is the fix that followed the P0 incident below; **2.1.0** added the department catalog and knowledge-skill routing; **2.1.1**–**2.1.2** decoupled manifest writes from materialize outcomes and made the post-apply doctor gate severity-based (warn no longer rolls back a verified manifest) plus added cold-start mirror seeding; **2.1.3**–**2.1.5** covered `resolve --explain` subpath joining, a never-destroy hold on a committed customization to a framework-owned file, and a verified-fallback fold behavior; **2.2.0**–**2.2.1** added `cc connections --json` and fixed the permanent-false-`needs-connect` honesty bug; **2.3.0** added `cc connect`, the stdin-only secret-input verb.

**A P0 incident happened and was fixed within this arc.** On 2026-07-27, `cc` materialization deleted 12,537 lines of organization content in `knowledge-copilot-internal` through the `~/.claude/knowledge` symlink (a personal-layer reconcile-delete that a vault cron then pushed). It was found by the inheritance-readiness audit (WP-372) and restored, and `cc` 2.0.3's guard is live-proven refusing the same shape on replay. This is why "never-destroy guard" is a headline fix, not routine hardening.

**The app got a truthfulness pass, then a visual pass.** Phase 7's app-side work made "Try again" retryability-gated and rendered the completed-actions ledger instead of a false "nothing changed." This session's P1 visual refresh (`native/design-system.swift`, task 222, WP-404/405) fixed a genuine defect where cards were architecturally invisible — `NSColor.controlBackgroundColor` and `.windowBackgroundColor` resolve to the *same* value on current macOS (1.00:1 contrast), so every card had been rendering as a flat, edgeless page — and shipped a token-based type/color/state system plus the Connect sheet, the in-app UI for writing a secret into the keychain over stdin.

**Current honest degraded state, verified live:** `cc connections --json` reports `store.reachable: false`, `store.diagnostic: "Error: Authentication failed — check INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET"`, and a service mix of **12 ready / 8 no-store** (`uspto`, `crm`, `brevo`, `n8n`, `coolify`, `insights`, `project`, `conv` — confirmed by listing every non-`ready` row). This is a server-side rejection of this machine's Universal Auth credential, not a local one: the keychain-resident `INFISICAL_CLIENT_ID`/`_SECRET` read fine locally, Infisical's own server rejects them. The fix is the owner's Infisical dashboard re-mint (§3), not a local credential re-probe (§5's Credentials doctrine covers the distinction).

---

## 2. The big decisions of record

**ADR-006 — Ecosystem setup is a preflighted saga.** History classification is a closed 8-state function (now 9 with the parentless-snapshot addendum); only a merge-base-proven fast-forward may claim a clean repair; every deterministic preflight runs before any irreversible GitHub write; a `completed_actions` ledger makes "nothing changed" a claim that must be true.

**ADR-007 — Onboard schema v2.0, a breaking bump.** Every `ecosystemLayer` row now requires its topology fields; a `layers_state` enum (`reported`/`not-computed`) makes an empty `layers: []` array only legal when explicitly typed that way — closing the exact ambiguity that let the 0.2.4 release ship with a silently-empty topology array.

**ADR-008 — `repair` and `publish` verb scoping.** History remediation lives inside `cc onboard`'s own routing, not a standalone `cc repair`. `cc publish` (the author-side writable-tier push) is formally deferred — designed in `inheritance-and-publish.md`, not implemented, not scheduled under this initiative.

**ADR-009 — Self-service store provisioning, B′ rulings ratified (2026-08-03).** Adopts all eight owner rulings from the security review's §11.8 list verbatim: 15-minute Infisical `accessTokenTTL`, 90-day signing-key rotation, `enforce_admins: true` on `claude-copilot-internal` (applied live the same day — verified: `enforce_admins.enabled` reads `true` via `gh api` as of this document), a 30-day evidence-gated admin-pair retirement, hardware-key MFA and DNS/registrar custody as owner-hands requirements, and evidence-gated (not calendar-gated) admin-pair retirement. **It ratifies parameters and one governance fix — it does not authorize building the B′ broker itself**, which remains a fully unbuilt next initiative.

**The six 2026-07-31 owner ratifications** (recorded verbatim in `cc memory`, entry `9b30dd30`, "proceed all phases, no further checkpoints"): (1) Accounting is a real entitled department, target stays 16 layers; (2) the phase-6 handoff's finding 5 (signed helper returning empty `layers`) was a schema/emitter defect, not PyInstaller — no rebuild work scheduled; (3) ADR-006 and ADR-007 approved; (4) `cli-copilot`, `cli-copilot-internal`, and `codex-copilot` are accepted as manual-resolution cases, never auto-repaired; (5) `cc publish` formally deferred per ADR-008; (6) G-10 (scrub/rotate/publicize the two private foundations) is sequenced last.

**The protocol three-level override chain is live but incomplete.** Foundation-tier protocol works as the base. The company (org-tier) protocol is scaffolded at `claude-copilot-internal/commands/protocol.md` and wins the fold — `shadowed[]` proves it — but the org tier has **no trusted signer**, so it cannot materialize yet; `cc` 2.1.5's verified-fallback keeps foundation content flowing with the substitution honestly reported rather than silently. Activating company-tier overrides needs **one owner security ratification: trust a signer for org-tier content** — this is an open decision, not a code gap (§3). Project-tier protocol is verified governing via a deference clause added at the instruction level, since Claude Code's own precedence is personal-over-project by default and the clause corrects that at the instruction layer, not by changing the underlying precedence.

**Personal voice is scaffolded, not written.** Ten template files exist at `knowledge-copilot-private/personal/*.md` with `TODO(pablo)` markers, plus a personal-extension binding wired for precedence. The content is the owner's own words to write, not a build task.

**`publish` and `repair` remain formally deferred** per ADR-008 — this is unchanged from Phase 7 and restated here because it is easy to assume otherwise once so much else has shipped.

---

## 3. Open items — owner

| Item | Exact action | Evidence |
|---|---|---|
| **Infisical re-mint** | Regenerate this machine's Universal Auth client secret at the org's Infisical dashboard (`secrets.ineedacopilot.com`), then paste it into the app's Connect sheet or run `echo '{"INFISICAL_CLIENT_ID": "...", "INFISICAL_CLIENT_SECRET": "..."}' \| cc connect infisical --json`; then re-run `cc connections --json` and confirm 20/20 ready, then re-run `cc onboard --org Everyone-Needs-A-Copilot --json` and confirm the `layer-manifest` stage no longer wants a repair | Live-verified today: 12 ready/8 no-store, `store.reachable: false`; runbook is `docs/06-deployment/connecting-a-machine-to-the-shared-store.md` |
| **n8n two-secret rotation precaution** | Recorded in session memory as an outstanding precaution — two value-prefixes were briefly rendered in tool output on 2026-08-03. This was **not independently re-traceable** beyond the memory note during this document's verification pass; treat as flagged-not-confirmed and re-derive the exact exposure before deciding whether rotation is actually required | `cc memory search "n8n"` → entry summarized in `prd15-transaction-fix-shipped.md`; no corresponding WP or git evidence found |
| **Infisical console hardware-key MFA** | In the Infisical console's org security settings, enforce MFA org-wide, then register a hardware-backed authenticator (FIDO2/WebAuthn or a platform authenticator like Touch ID) on every console/platform-admin account, before that console creates the first per-scope B′ identity | ADR-009 item 6 / ruling 6 |
| **Registrar/DNS custody for a future broker hostname** | At whichever registrar will hold the B′ broker's discovery hostname: enable 2FA on the registrar account, enable Registry Lock/transfer lock, enable DNSSEC, and separately ask Infisical in writing whether a pinned/static JWKS is supported | ADR-009 item 7 / ruling 7 |
| **Org-tier signer ratification** | Decide and ratify a trusted signer for org-tier protocol/config content — this single decision activates the company-protocol override that is currently scaffolded but honestly falling back to foundation | `cc memory` entry `prd15-transaction-fix-shipped.md`, TASK-220/WP-384/385/387 |
| **Personal voice, company protocol, and department content** | Author the actual words: the 10 `TODO(pablo)` personal-voice templates in `knowledge-copilot-private/personal/`, the org protocol content once a signer is ratified, and real Accounting-department content (the routing surface works today; the four `*-copilot-accounting` repos are structurally live but content-empty) | `prd15-transaction-fix-shipped.md`; live manifest confirms all four accounting layers are populated paths with no content audit performed here |
| **V-5 cold-laptop proof** | Run the two-machine onboarding proof: a second Mac starting with an empty keychain and no work SSH key onboards, clones both mirrors via `copilot update`, and resolves every service from inherited config plus the store, with no hand-copied secret and no `.env` | `tc task get 218` confirmed still `status: pending`, depends on task 216 (done) |
| **Scrub → rotate → publicize `knowledge-copilot`/`cli-copilot`** | Last, irreversible: history-scrub the committed `.env`/`.env.bak`/`.env.production` exposure, rotate any credential that was ever committed, then flip both repos from private to public on GitHub | `tc task get 217` confirmed still `status: pending`; live `gh repo view` confirms both repos are still `PRIVATE` while `claude-copilot`/`codex-copilot` are `PUBLIC`; see `cc memory` entry `knowledge-copilot-live-secrets-in-git` for the exposure history and the prior scrub attempt that was cleanly rolled back |

---

## 4. Open items — next build initiatives

| Item | What it is | Status |
|---|---|---|
| **The B′ provisioning broker** | The GitHub-verified, admin-free self-service store-provisioning design (`docs/05-security/self-service-store-provisioning.md`) — ratified by ADR-009, threat-modeled twice (0 Critical / 3 High / 9 Medium / 5 Low across 17 findings), rendered in walkthrough 16. **Nothing is built**: no broker, no `cc connect --provision`, no `cc store verify`, no per-scope Infisical identities, no GitHub App `Members: read` wiring. This is a full next initiative, not a continuation task |
| **G-10, the `copilot`-CLI vendoring/install gap** | Control Tower vendors only `cc`; the `copilot` service CLI is not vendored or installed by any onboarding stage, so on a genuinely fresh Mac step 6 degrades to `copilot-unavailable` before any store question is even reachable. Every store-connect gap this phase's design work addresses is masked by this one gap on day one, because the owner's own dogfooding machine is never in the fresh-Mac state this would expose | WP-395 finding G-10, `Medium` complexity, unscheduled |
| **P2 visual-refresh items** | Deliberately deferred by the P1 pass's own spec split: the wizard's project-triage cards, two hand-built `CTChip` candidates, Holding-view `CTCalloutNote`/`CTDecisionBlock` adoption, sheet chrome for `InstallHelperSheet` and similar, and Admin surfaces beyond what `StepShell`/`CTCard` already inherit for free | WP-405, listed as explicitly out of scope for P1 |
| **`systemGreen`/`systemOrange` light-mode contrast drift** | `CTColor.state(.ready)` and `.state(.attention)` measure 4.29:1 and 4.44:1 in light mode on the current OS build (macOS 26.5.2) — both under the 4.5:1 floor and under the spec's own documented 4.93:1/5.11:1. Dark mode matches the spec almost exactly. Traced to Apple's `systemGreen`/`systemOrange` RGB values drifting slightly between OS builds, not an implementation bug — the 0.35 blend fraction is a spec-authored value. Flagged for the spec owner to decide whether to retune it | WP-405 finding, unfixed by design (spec-owner call, not an implementation bug) |
| **The recurring `uv.lock`-bump defect** | Every `cc` version bump has needed a manual `uv.lock` regeneration alongside the `pyproject.toml`/`__init__.py` edits; this has now recurred at least three times this arc (the 1.7.16→2.0.0 bump, the 2.1.2→2.1.4 bump, the 2.1.4→2.1.5 bump). Worth automating as a pre-commit or release-script step rather than continuing to catch it by hand each time | Confirmed via `git log`/WP-370, WP-384, WP-385; no automation task filed yet |
| **P5.3 — the `refs/copilot/lock` freshness-pointer decision** | Decide whether to publish `refs/copilot/lock` so `cc freshness` stops returning nulls. Until this is decided, Control Tower's freshness tile is permanently "unknown" by honest design, not by a bug | WP-372, explicitly named as "genuinely a next initiative," not closable by a single session |
| **Stale doc: `foundation-release-signing.md`** | Its "Current status" section still reads "Public release tags and compiled signer fingerprints remain blocked until a dedicated ENAC release key is selected, registered, and approved" — but per WP-410/prior sessions, the ENAC key is already both GitHub-registered and compiled into `policy.py`'s `FOUNDATION_SSH_SIGNING_KEYS`. Confirmed stale by direct read of the file (line 102-106) during this document's verification pass | Doc-only fix, unscheduled |

---

## 5. Standing doctrine a new session must know

**The six invariants govern everything.** See `CLAUDE.md` at repo root — parse-never-compute, single process, never-destroy, security posture inherited-and-enforced, route by actor-competence × reversibility, and one-way inheritance with secrets never traveling in it. Note: the 40 `fitness_*.rs` tests that were meant to enforce these scan the retired `src-tauri` Rust tree, not the ~22,650 lines of shipping Swift in `native/`, and the CI job that runs them is disabled. The invariants are upheld by review today, not automatically enforced — see `cc memory` entry `invariants-stated-not-enforced` and `docs/04-validation/audit-2026-08-02-findings.md` finding C1.

**Credentials doctrine (in `CLAUDE.md`, added this arc).** This machine is fully provisioned. A **local** "credential not found" — from a headless, backgrounded, or locked-keychain context — is a probe artifact until re-verified from the interactive session; never ask the owner to re-provision on the strength of a local not-found alone. A **remote** rejection of a credential that reads fine locally, evidenced by server-side logs (exactly the Infisical `reachable: false` state in §1), is genuinely dead and is real owner action. This doctrine exists because a release agent once declared the `ct-notary` notarization profile missing and asked the owner for a new Apple password, when the profile was present and working the entire time — a locked-keychain read from a background context had returned a false negative.

**The two-names trap.** `copilot`/`cc` each name two different things in this ecosystem. Control Tower's CLI contract is against `claude-copilot`'s `cc` (the ecosystem-setup/onboard/connections engine, vendored into the app at `Contents/Resources/cc`). It is **not** the same program as CLI Copilot's own `copilot`/`cc` binary (the service-integration CLI, installed separately, the one that is not vendored — see G-10 in §4). Confusing the two produces wrong diagnoses; always check which repo and which `--version` output you are actually looking at.

**The lockfile-collision cwd rule.** Run `cc onboard`/`cc connections` read-only commands from a neutral working directory (`/tmp`, `$HOME`) — never from inside `claude-copilot`'s own checkout. `claude-copilot` is itself a Copilot-managed project with its own `copilot.lock.json`; running `cc` from inside it collides the tool's own lockfile resolution with the project it happens to be sitting in. Every verification command in this document was run from `/tmp` for this reason.

**Sibling-session coordination.** More than one session/agent can be active in this tree at once (a bridged Discord continuation, a background release agent, a live terminal session). Before editing shared files — especially `native/*.swift`, the manifest, or any in-flight release branch — check `git status` for foreign uncommitted work and check whether a sibling session's commits have already landed; `git pull --rebase` reporting "nothing to do" after a shared checkout picked up commits mid-session is the expected, safe outcome, not a sign something is wrong. See `cc memory` entry `bridge-session-collision`.

**Never-destroy incident history, in one paragraph.** On 2026-07-27, `cc` materialization walked through the `~/.claude/knowledge` symlink into `knowledge-copilot-internal` (a shared org repository) and reconcile-deleted 12,537 lines of content that a vault cron then pushed to `origin/main` as a routine-looking backup commit — the guard that should have refused a personal-tier materialization pass from writing into a symlinked shared-tier target did not yet exist. It was found nine days later by an inheritance-readiness audit (WP-372), fully restored (all five deleted agent extensions, the manifest, the consumption contract), and `cc` 2.0.3 added a four-check guard ladder — including an explicit symlink-escape check and a clean-tracked-repo-with-remote check — that has since been live-proven refusing the exact same shape on replay. This is the reason "never-destroy guard" appears as a headline fix in §1 rather than routine hardening: it closed a real incident, not a hypothetical one.

---

## 6. Learning path

Read in this order before touching code or running any live command:

1. **This document**, for the current state and the open fronts.
2. [`CLAUDE.md`](../../../../CLAUDE.md) at repo root, for the six invariants and the Credentials doctrine.
3. [`phase-7-transaction-fix-and-owner-runbook.md`](phase-7-transaction-fix-and-owner-runbook.md), for the transaction-fix history and the review-row resolution log this phase built on.
4. `tc wp get 395 --json` and `tc wp get 396 --json`, for the Bob-in-accounting trace and the Connect-experience walkthrough that motivated the self-service-provisioning design.
5. [`ADR-009-self-service-store-provisioning-rulings.md`](../decisions/ADR-009-self-service-store-provisioning-rulings.md), for the ratified B′ parameters and the one governance fix already applied live.
6. [`walkthrough 18`](../walkthroughs/18-self-service-provisioning-uxd-walkthrough.html), for the rendered self-service provisioning experience both actors (Bob and the admin) would see if the B′ broker were built.

Everything is recorded in two places: **Task Copilot** (`tc prd get 15 --json` for the phase-7 gap closure; `tc wp list --task 220/221/222 --json` for the protocol/connections/self-service work; `tc task get 217/218 --json` for the two still-pending owner-gated tasks) and **`cc memory`** (`cc memory search "<topic>"` — `prd15-transaction-fix-shipped` is the terminal-state index entry for this whole arc; `credentials-exist-probe-before-asking` is the standing doctrine now also in `CLAUDE.md`).
