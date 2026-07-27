# Phase 6a — Honest setup: Holding, adoption, and organization sign-in (work record)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-6-ecosystem-install-and-onboarding-proof.md`](phase-6-ecosystem-install-and-onboarding-proof.md) (the aggregate `cc onboard` transaction, and the two-machine cold-start proof it defines). This sub-phase does not add onboarding machinery; it closes dead ends that dogfooding Phase 6 on a real Mac exposed in the wizard and in the CLI stages that back it.
> Companion document: [`phase-6-honest-setup-handoff.md`](phase-6-honest-setup-handoff.md) — state, blockers, open decisions, and how to resume. This document is the retrospective: what was wrong, what changed, and why. Read the handoff first if you are picking this up cold; read this one to understand the reasoning behind what you inherited.
> Covers nine commits across two repos, unmerged and unpushed as of this writing: `copilot-control-tower` branch `app-build` (`dca7e58`, `9d4730f`, `a3884b0`, `19850ec`, `1aef610`) and `claude-copilot` branch `feat/adopt-and-project-setup` (`e3e1826`, `8efe9ad`, `44fcfa5`, `20886b3`).

## How this started

The user launched the end-user app and saw "Setup is holding / I've paused the setup." with no reason given and no action offered. That one screen was serving ten different underlying conditions, and tracing why led to five more problems, each uncovered by fixing the one before it. This document tells that chain as five problems, not nine commits, because the two repos changed together: on both session days, a CLI commit and an app commit landed one to three minutes apart, the app consuming a CLI fix that had just shipped.

## The through-line

**A screen must never imply something that isn't true, and it must never leave the person with no way forward.** Every problem below is that same defect in a new place. The sharpest instance of it: the first fix made the dead end *politer* without making it *passable* — a calm screen over an incomplete setup, which is worse than an obvious failure, because the person walks away believing they are done. The user caught that mid-session, and it is why the completion rule (problem 2 below) exists as an enforced, checkable rule rather than an editorial habit.

---

## Problem 1 — one screen, ten meanings

**Where:** `copilot-control-tower`, commit `dca7e58`.

The wizard's `.holding` phase rendered one screen — "SETUP IS HOLDING" — for every condition that could stop setup. `genericHoldingReason` collapsed five distinct `CliError` cases (`.launchFailed`, `.parse`, `.schemaOutOfRange`, `.missingSecurityField`, unmapped `.exit2`) into a single sentence, and its `.exit2` branch never bound the code and message it already held, so the CLI's own explanation was computed and then thrown away.

Worse, the same screen served two opposite meanings. A genuine fault and "I found something you already own and refused to overwrite it" rendered identically. The second case is invariant #3 (never-destroy) working exactly as designed; presenting it as a crash taught people to distrust the mechanism that was protecting them.

**The fix:** Holding became six variants, chosen by **who owns the fix**, never by what went wrong — H1 not installed (neutral, install steps behind one tap), H2 can't read your setup (the five `CliError` cases, each with its own honest sentence), H3 couldn't finish a part (a real stage fault), H4 something here is already yours (blue, never "paused" or "failed", primary action "Keep what I have"), H5 waiting (offline, or another update in progress), H6 waiting on your organization (nothing for the user to do, with the artifact to hand IT). A CLI-authored message is framed under its own label when it was written for a person, and hidden in a collapsed support block when it names machinery — never a headline, never interpolated into an app sentence. Every variant has at least two exits, one of which works offline with a broken CLI. `Let setup manage it` deliberately renders nowhere yet: no CLI consent path exists for any blocked gate, and offering a permission the CLI would not honor is the same lie this change removes. H3 is the default whenever nothing positively proves a hold is user-owned, because wrongly telling someone "this is yours" would be worse than the original bug.

**Deferred, flagged, not fixed here:** `native/render-state.swift:116` still folds `CliError.notFound` into `.ioError` for the tray, one layer up from the same misdiagnosis this change removed from the wizard. Confirmed still present as of this writing.

**Design record:** `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/holding-copy-spec.md` (historical — six variants; superseded by problem 3 below, which adds a seventh).

---

## Problem 2 — a calm screen over an unfinished setup

**Where:** `copilot-control-tower` commit `9d4730f`, paired one minute later with `claude-copilot` commit `e3e1826`.

A person with an existing `github-work` or `github-personal` SSH alias hit H4, "Something here is already yours", with primary action "Keep what I have". Clicking it said "Kept as it is. Control Tower keeps watch from the menu bar." — but five of seven onboarding stages had never run and nothing downstream was installed. The sentence was true about the decision the person had just made and false about setup, and it printed only the true half.

Tracing this to its root cause landed in the CLI, not the app. The `device-ssh` stage's check (`ssh_identity.py`) was a string scan for the CLI's own sentinel comment in `~/.ssh/config`: no marker found meant "foreign", and foreign meant stop, without ever testing whether the connection actually worked. This is the irony the CLI commit message names directly: this stage is the *only* thing that creates the `github-personal` alias, so it was refusing to run because of the alias that already worked, and by refusing, it never created the one that was missing. This was unfinished work, not a decision — a sibling gate (personal GitHub packages) had already been fixed to adopt instead of refuse in an earlier commit (`6398bb4`), and `ssh_identity.py` was never swept along with it.

**The CLI fix:** an unmanaged alias is now adoptable when four checks pass — it reaches GitHub under `BatchMode`, it signs in as the same account the app is signed in as, it resolves to the expected host, and it can actually reach a repository. Anything short of that stays held, because wrongly telling someone "this is yours" is worse than stopping; a different login stays held on purpose. Adoption is additive: the working block is never touched, and the missing alias is prepended in its own sentinel block so SSH's first-match-wins resolution cannot let an earlier `Host *` silently override it. Verified read-only against a real machine whose alias authenticates and whose token lacks a GitHub scope (see problem 2's aftermath, problem 6 below): the stage reported adoptable for the connection, `~/.ssh/config` was never written, and its checksum was identical before and after.

**The app fix, and the real deliverable of this problem:** rather than patch the one sentence, the rule was put into code as a checkable predicate — **the completion rule.** A screen may use resolved language (*kept*, *done*, *set up*, *ready*, *checks out*, *everything*, *all*) only when all four hold of the report it renders: (1) `result` is `applied` or `ready`, never `changes-required` or `blocked`; (2) no stage in the report has `result: "blocked"`; (3) every stage the schema names appears in the report — a stage never mentioned counts as not done; (4) the sentence describes only what the report proves, never generalizing from a decision to the whole of setup. Failing any one of the four routes to a shared fallback pattern, "Here's where that leaves you" (`docs/03-design/control-tower-copy-deck.md` §2.10), with two lists in the reader's own words — what works now, what doesn't work yet — and deliberately **no fraction**: "5 of 8 done" answers a question the person did not ask and invites them to judge severity, which invariant #5 refuses to hand them. `Kept as it is` is deleted outright rather than conditioned: it hung off a screen only reachable from a blocked result, so it could never have been true, and conditioning it would imply a passing case existed.

With the CLI now verifying instead of refusing, the hold became an offer and joined the "one question first" screen the wizard already used for existing personal content: a second card for machine-scope rows, alongside the existing GitHub-account card. The row states the check that happened and what will be left alone; the app's own reassurance line carries the never-destroy promise on a separate track, so the guarantee never depends on the CLI getting a sentence right.

**Two bugs would have made all of this render as nothing**, both now covered by tests that fail if they regress: `personalOnboardQuestion` filtered inventory to `scope == "personal"`, so the machine-scope row was silently dropped and the offer never appeared; and `componentId(fromPersonalInventoryId:)` returned `nil` for `device-ssh` (its id carries no `personal-` prefix), so answering "yes" would have sent no consent token, written nothing, and re-asked forever.

A seventh Holding variant, H7, was added for the one gap this pass could not close: a GitHub sign-in missing the `admin:public_key` permission needed to register the Mac's key. None of the other six variants fit — the fix is the person's own, it is a real fix rather than a decision, and they can do it themselves. The verb that would turn this into a button (`cc auth grant`) does not exist yet, so H7 degrades honestly to the documented command with a note about who it is for, and never shows a button that does nothing.

**Self-correction recorded in the commit itself:** an earlier scenario (S18) had asserted the original block was *correct* behavior and called it "invariant #3 working" — that assertion was a misreading, and it shipped as a test. It was rewritten to assert the offer instead, keeping the genuinely-unsafe cases (different account, wrong host, no repository access, malformed config) as their own scenario, still held by default.

**Design record:** `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-honesty-copy-spec.md` (STATE 1 and STATE 2 sections; STATE 3 is problem 6 below).

---

## Problem 3 — a variant with no way back to it, and a checkbox that lied

**Where:** `copilot-control-tower` commit `a3884b0`, paired with `claude-copilot` commit `8efe9ad`, both landed in the same minute.

H7 (problem 2's new variant) told someone their GitHub sign-in was missing a permission and that they alone could grant it — then `Continue in the menu bar` closed the wizard with no prompt, no reminder, and nothing to come back to. The one variant addressed to the person themselves was the one with no path back.

The fix reused a seam that already existed rather than building a new one: the `connection-offer` notice (problem 2's menu-bar element) already re-derives itself from the read-only plan on every refresh. A `permission-needed` prompt copies that shape, keyed on the `device-ssh` stage reporting `not-permitted` — a CLI-emitted enum token, never sniffed from prose — with its button reopening the wizard directly onto H7. It renders as a **prompt**, not a notice, because unlike the connection offer, the person here can act on it immediately.

A structural defense was added alongside it: any reversible inventory row whose id has no consent-token mapping now renders as a review row with no checkbox at all, rather than as a checkbox that silently does nothing when answered. This closes the *class* of bug that the `device-ssh`-maps-to-`nil` defect (problem 2) already demonstrated once; a debug assertion and a self-test make a future unmapped id loud instead of silent.

On the CLI side, the same adversarial pass (`8efe9ad`) found two more instances of the pattern this whole effort exists to remove: a checkbox that did nothing (manifest repair/migrate rows were marked `reversible: true` and rendered as clearable, but the repair ran regardless of the answer — fixed by marking them `reversible: false`, since these rows write to an existing recognized file behind a content-addressed backup, which is a safety net and not consent, and invariant #5 says this is exactly the kind of internal plumbing to act on rather than ask about), and jargon reaching the always-visible Set Up checklist rather than only the collapsed support block (`alias`, `device`, and raw `github-work`/`github-personal` names, rewritten in plain words).

**Design record:** `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-honesty-copy-spec.md` §3 (STATE 3, H7).

---

## Problem 4 — a deadlock that made sign-in impossible on a fresh Mac, and telling an admin there was nothing they could do

**Where:** `claude-copilot` commit `44fcfa5`, followed three minutes later by `copilot-control-tower` commit `19850ec`.

Sign-in was unreachable on any Mac that had never already signed in. The client id was resolved from local config, and failing that from `~/.claude/ecosystem.yml` — a file nothing in either repo has ever written, so that fallback could never fire. Underneath it sat a genuine deadlock: signing in needs the client id, the client id was published only to the organization's private repo, and reading a private repo needs to already be signed in. Admin standup was not at fault — it created the app and published the id exactly as specified — but delivery to a user's own machine was never built, and the contract describing that delivery had assumed it into existence without specifying it.

**The fix:** the client id is public by ratification, so it does not need to hide behind auth. It now comes from a small public artifact — org name and client id, nothing else — fetched over a plain, unauthenticated HTTPS request before any credential exists. The dead `ecosystem.yml` fallback branch was removed rather than left in place as something that could never fire, and "no app exists" is now told apart from "nobody told me which organization", which had previously been the same error (this second code, `org-required`, is what problem 5 below answers).

**Separately, and more serious: this test suite wrote to the developer's real machine.** An onboard test passed a manifest path through to `write_config` without stubbing it, and `machine_config_path()` resolved `Path.home()` with no override seam, so a test run edited the live `~/.claude/cc/config.json` and left a pytest tmpdir path in it. This had been sitting there, undetected, before anyone looked. Every test now gets an isolated config root automatically (`CC_MACHINE_ROOT`), and the suite checksums the real files before and after and fails if they moved. This is prevention plus detection, chosen over threading a root parameter through a dozen call sites — the plumbing a contributor can forget to pass is exactly what caused the incident. The same sweep flagged, but did not yet fix, the global memory root, which had no override at all.

**The app-side fix:** a real user hit "Your organization hasn't finished setting up sign-in yet. There's nothing for you to do." — while being the org admin, standing on the very Mac where they had run standup. Both halves of that sentence were wrong. For anyone, the false "nothing to do" clause was removed and the handoff — "copy details for support" — was promoted from a collapsed disclosure to the screen's actual primary button, reusing the same call problem 2's completion-rule pattern already made: whoever needs it copies it in one click, whoever wants to read it still can. For an admin specifically, a local, honest signal now exists: the standup brief this Mac's own admin app already writes (`~/Library/Application Support/CopilotControlTower/standup-brief.json`) carries the client id, so the app can name the exact fix — `cc config set github_app.client_id <id>` — instead of gesturing at one. This routes to H7 rather than an eighth variant, because it is the same ownership H7 already encodes: the fix is the person's, it is real, and they can do it here. A compile-time build-flag check was considered and rejected, because the actual failure case — a user build running on the admin's own Mac — is exactly what a build-time flag cannot see; the brief is read by path rather than through the admin-only `AdminPaths` type, for the same reason. The signal is proven fail-safe in both directions: brief absent stays on the ordinary org screen; brief present with a readable client id routes to the self-serve fix; brief present without a readable id stays on the ordinary screen rather than promising a command it cannot fill.

A second, narrower completion-rule violation was fixed in the same commit on the admin side: the Admin "Handed off" screen ended by promising "send them the app, and they'll see the departments they're on" — a specific claim about a machine the admin app had never touched, and false for every user in the org until the sign-in id could actually reach them. It now says only what the check proved (the GitHub side, nothing about any user's Mac) and names the first real sign-in as the actual test (`native/admin-support.swift:1730`).

**Design record:** the deadlock and the public-artifact fix are recorded in the CLI commit message directly; there is no separate copy spec for this problem (it is infrastructure, not new user-facing copy beyond the H7-self-serve strings already in `docs/03-design/control-tower-copy-deck.md` §2.9).

---

## Problem 5 — asking the missing question, and three more bugs a human answering it exposed

**Where:** `claude-copilot` commit `20886b3`, landed in the same minute as `copilot-control-tower` commit `1aef610`.

The CLI's new public-artifact fetch (problem 4) still needed to know *which* organization's artifact to fetch, and nothing on a genuinely fresh Mac supplies that. `cc auth login` gained an error code for exactly this — `org-required`, meaning "nobody has told me which organization you're with" — distinct from `no-company-app` ("I know your organization, and its sign-in isn't set up yet"). The app had no case for the new code, so it fell to the catch-all H2, "Something stopped me from reading your setup, so I won't guess." — on every fresh Mac, since the app never passes an organization and never sets one. Two repos had changed out of step, and the result was the exact dead-end class this whole effort exists to remove.

**The app fix:** the CLI cannot ask, because it must stay non-interactive and machine-readable — so asking is the app's job. An inline screen over Connect GitHub (the wizard's first text field) asks which organization, styled blue as a question rather than a pause, using the same `StepShell`-over-a-stage mechanism the "one question first" screen (problem 2) already established. Before asking, the app exhausts what it can already know: an organization pointer already set on this Mac, then the admin standup brief's `org` field, tried silently with nothing rendered — a confirmation screen there would say nothing but "everything is fine, press Continue," which is the one thing this product refuses to render anywhere. Nothing is persisted until sign-in actually starts, so a stale or wrong name leaves nothing behind. The field accepts a pasted GitHub address as happily as a bare name and rewrites it in place (`https://github.com/Acme-Co` → `Acme-Co`); text it cannot reduce is left for validation to answer rather than silently discarded. Every one of the four resulting codes now routes somewhere real: not-found keeps what was typed so the difference stays visible; offline goes to the existing offline screen instead of blaming the organization; and waiting-on-your-organization gained a way back (`Use a different organization`), because `Acme` and `Acme-Co` can both be real organizations, and typing the wrong one would otherwise strand someone waiting forever on an admin with nothing to fix.

**Three CLI bugs surfaced once it became clear a human would be typing the organization name** — the same collapse-every-failure-into-one-code pattern from problem 4, now revisited because asking a person changes who owns each failure:

1. **Case-sensitive organization comparison.** `fetch_org_client_id` compared the bootstrap file's `org` field with an exact string match. Someone told `Acme-Co` who typed `acme-co` got a mismatch, a fail-open `None`, and H6 telling them their organization hadn't finished setting up sign-in — when it had. GitHub logins are case-insensitive and unique by fold (an earlier commit, `401b585`, had already established that real organization names must be sent verbatim, capitalization included). The comparison now folds case for the match while still sending the value to GitHub exactly as published.
2. **A typo and a real-but-unpublished organization shared one code.** A new code, `org-not-found`, now comes from an unauthenticated check that the organization resolves on GitHub at all. Its fail direction is deliberately pinned: an inconclusive or rate-limited probe degrades to `no-company-app`, never to `org-not-found`, because telling someone their real employer does not exist is worse than making them wait — and the unauthenticated GitHub rate limit (60/hour) is shared by everyone behind one corporate address, so inconclusive answers will be routine, not rare.
3. **An offline Mac was told a fabricated state.** A transport failure fetching the bootstrap artifact used to become `no-company-app` too, so an offline person read "your organization hasn't finished setting up sign-in yet." A new code, `network-unavailable`, routes this to the existing, honest offline screen instead.

**Hardening done in the same commit, because this is the one request that runs before any credential exists:** the bootstrap fetch now refuses any URL that is not HTTPS on the pinned `raw.githubusercontent.com` host and caps the response size it will read. A configurable host allowlist was considered and rejected as relocating the same trust problem rather than solving it — invariant #4 says security-critical values come from compiled-in trust roots or signed inherited config, never user-editable local config.

**The test-isolation gap from problem 4 was also closed here, and closed harder than "detected."** Review demonstrated that the checksum-only detection added in `44fcfa5` could still be defeated: a probe that cleared the `CC_MACHINE_ROOT` override and called the write path directly wrote to the real config, and only the teardown checksum noticed, after the fact. For a failure whose entire danger is silence, noticing afterward is not enough. A `write_guard` module now hard-refuses, at write time, any path that resolves to or inside the real `~/.claude/cc/config.json`, `~/.claude/cc/secrets.env`, or `~/.claude/memory`, gated on pytest's own `PYTEST_CURRENT_TEST` sentinel rather than the override env vars a test could separately monkeypatch around. The global memory root — flagged but not fixed in `44fcfa5` — got the same override seam (`CC_GLOBAL_MEMORY_ROOT`) in this commit. A latent default-argument-binding hazard was also fixed: Python binds default parameter values once, at module-import time, so a `param: T = real_impl` default silently defeats the usual `monkeypatch.setattr(module, "real_impl", fake)` seam for any caller that omits the keyword; injected collaborators in the onboard path now resolve at call time instead.

**Design record:** `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/org-question-copy-spec.md`.

---

## Test growth across the sequence

Both suites grew monotonically as each problem's fix landed; the counts below are self-reported per commit message, not independently re-derived (see the companion handoff document for a from-scratch verification run and a flagged discrepancy in the CLI count).

| Session point | App: smoke scenarios | App: admin bootstrap suite | CLI: pytest |
|---|---|---|---|
| Before this sequence (`08ddd9a`) | 58 | 196 | 1,053 passed / 14 skipped (pre-`e3e1826`) |
| Problem 2 (`9d4730f` / `e3e1826`) | 68 | — | 1,053 passed / 14 skipped |
| Problem 3 (`a3884b0` / `8efe9ad`) | 74 | — | 1,054 passed / 14 skipped |
| Problem 4 (`19850ec` / `44fcfa5`) | 87 | — | 1,076 passed / 14 skipped |
| Problem 5 (`1aef610` / `20886b3`) | 110 | 206 | 1,100 passed / 14 skipped |

---

## Invariant reasoning, by decision

| Decision | Invariant | Why it applied |
|---|---|---|
| The app never computes which Holding variant means what beyond decoding CLI-emitted enum tokens (`hold`, `registration`, `config`, `action`) | #1 parse, never compute | Every discriminator in `holdingInfo(forBlockedOnboard:)` reads a token the CLI emitted; none infers from prose. Claiming "this is yours" without proof would be worse than the original bug. |
| Adoption of an existing SSH alias or GitHub package is additive only; the working block is never touched, and a differently-authenticated alias stays held | #3 never-destroy | The entire H4 taxonomy exists because setup found something the person already owns; the fix had to stop *wrongly refusing to build around it*, not start overwriting it. |
| The bootstrap artifact fetch is pinned to one HTTPS host with no user-editable allowlist; the org pointer is never accepted from anywhere but the app's own deliberate write | #4 security never weakened | A configurable host list would relocate, not close, the one request that runs before any credential exists. |
| H7 (a missing GitHub permission) is addressed to the person with a button, never to IT with a copyable command; the org-name question is asked of the person, never inferred or guessed | #5 route by actor-competence × reversibility | The fix is genuinely the person's own and nobody else's; routing it to IT would hand the work to an actor who cannot perform it. Conversely, manifest repair/migrate rows were changed from an ask to a told-about action, because the person cannot judge that plumbing (also #5). |
| The org name pointer is written to local machine config only after sign-in actually starts; it never appears in any git repo; the client id is public but the client secret is never collected | #6 secrets never travel in inheritance | Nothing about this problem set moved a secret; the one new artifact (`bootstrap.yml`) is deliberately scoped to two non-secret fields, enforced by a leak-scan guard in `admin_bootstrap.sh`. |

---

## What this document does not cover

Open decisions, unverified claims, known gaps, and the exact steps to resume are in the companion handoff, [`phase-6-honest-setup-handoff.md`](phase-6-honest-setup-handoff.md) — deliberately kept separate so a reader who only needs "what changed and why" is not made to wade through "what's left."

## References

**Both repos, as one story**

- `copilot-control-tower` branch `app-build`: `dca7e58`, `9d4730f`, `a3884b0`, `19850ec`, `1aef610`
- `claude-copilot` branch `feat/adopt-and-project-setup`: `e3e1826`, `8efe9ad`, `44fcfa5`, `20886b3` (branch base `f7f9412`; `6398bb4`/`25ae189` predate this sequence and are the sibling fix problem 2 references)

**Design artifacts** (copied into this initiative's `walkthroughs/` directory during this documentation pass, from the session scratchpad where they would otherwise have been lost)

- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/holding-copy-spec.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-honesty-copy-spec.md`
- `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/org-question-copy-spec.md`

**Ratified copy (current, supersedes the specs above where they disagree)**

- `docs/03-design/control-tower-copy-deck.md` §2.1.1/§2.1.2 (organization question), §2.2.1 (adopt offer), §2.9/§2.9.1/§2.9.2/§2.9.3 (Holding, seven variants), §2.10 (completion rule), Appendix D, Appendix E
- `docs/03-design/landing-site.md` §3.1, §6 (the organization-name carriers)
- `docs/01-architecture/schemas/auth.schema.json` (four `auth --json` error codes: `no-company-app`, `org-required`, `org-not-found`, `network-unavailable`)

**Code, current locations verified during this documentation pass**

- `native/wizard.swift` — `personalOnboardQuestion`, `componentId(fromPersonalInventoryId:)`, `holdingInfo(forBlockedOnboard:)`, `holdingInfo(forNonHealthy:)`, `holdingInfo(for:origin:)`, `holdingInfo(forExit2Code:message:origin:)`, `reopenForConnectionOffer()`, `reopenForPermissionNeeded()`
- `native/render-state.swift:116` — the still-deferred `.notFound`/`.ioError` tray fold
- `native/models.swift` — `LocalAdminSignal.standupGitHubAppClientID`, `.standupOrgName`
- `native/admin-support.swift:1730` — the corrected "Handed off" completion-rule claim
- `claude-copilot/tools/cc/src/cc/core/ecosystem/ssh_identity.py` — the adopt-instead-of-refuse `device-ssh` stage
- `claude-copilot/tools/cc/src/cc/core/ecosystem/bootstrap_config.py` — `fetch_org_client_id`, `org_exists_on_github`, the pinned-host fetch
- `claude-copilot/tools/cc/src/cc/commands/auth.py`, `claude-copilot/tools/cc/src/cc/commands/onboard.py`
- `claude-copilot/tools/cc/src/cc/core/write_guard.py`, `claude-copilot/tools/cc/src/cc/core/config_paths.py`, `claude-copilot/tools/cc/src/cc/core/entry_store.py` — the test-isolation prevention layer
- `scripts/admin_bootstrap.sh` — `_ensure_bootstrap_yml`, `_render_bootstrap_yml`, the public `copilot-bootstrap` repository functions (see the companion handoff for why these are unexecuted)
