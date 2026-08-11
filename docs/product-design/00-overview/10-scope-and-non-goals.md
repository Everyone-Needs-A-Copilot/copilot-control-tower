# Scope & Non-Goals

<!--
FACILITATION GUIDE — Service Designer
======================================
This document draws hard boundaries around the product. It is the
contract between ambition and reality. Everything in this document
is a decision NOT to do something — and each decision needs a reason.

PREREQUISITE: 00-vision.md must be completed first.

CONVERSATION FLOW:
1. Define what is in scope for the initial release
2. Define explicit non-goals (things we will NOT build)
3. Define anti-features (things that would actively harm the product)
4. Define constraints (things that limit what we can do)
5. Articulate the design philosophy that governs scope decisions
6. Define integration boundaries (what this will NOT connect to)
7. Capture future considerations (out of scope now, may come later)

QUESTIONS TO ASK:

## Round 1: Scope Definition
- "Looking at the core capabilities from the vision, which ones are
  essential for the first version? What could wait?"
- "If you could only ship THREE things, what would they be?"
- "What's the minimum experience that would make this useful?"
- "Are there specific use cases or user types to support first?"
- "What does the minimum scope look like across data, workflow, and output?"

## Round 2: Explicit Non-Goals
- "What features might people expect that you specifically do NOT
  want to build?"
- "What adjacent problems are you deliberately not solving?"
- "Are there user types you are NOT designing for?"
- "Is there a line between 'helping users do X' and 'doing X for them'
  — and where is it?"

## Round 3: Anti-Features
- "What would make this product worse if you added it?"
- "What feature requests should you say no to even if users ask?"
- "What would make this feel like every other tool in the space?"

## Round 4: Constraints
- "What technical constraints exist? (Budget, hosting, APIs, etc.)"
- "What business constraints exist? (Team size, compliance)"
- "Are there regulatory or compliance requirements to consider?"
- "What's the AI philosophy here — where does AI help vs. where must
  a human remain in the loop?"

## Round 5: Design Philosophy
- "What governing principles should every scope decision be tested against?"
- "If a feature request came in, what questions would you ask to decide
  if it belongs in this product?"
- "What would an over-scoped version of this product look like?
  What would have been added that didn't belong?"
- "How does Dieter Rams' 'as little design as possible' translate
  to this product's scope decisions?"

## Round 6: Integration Boundaries
- "What systems will this NOT integrate with, and why?"
- "Are there integrations users will ask for that you should say no to?"
- "What's the boundary between what {{PRODUCT_NAME}} does and what
  users manage externally?"
- "Are there compliance or data privacy reasons to avoid certain
  integrations?"
- "What integrations would pull this product away from its core job?"

## Round 7: Future Considerations
- "What is explicitly out of scope right now that might come later?"
- "What would you need to be true before you'd consider adding [X]?"
- "Are there capabilities you want but that are too complex or costly
  for the first version?"
- "What is the V2 wishlist? What earns its way in through adoption?"

SYNTHESIS:
Organize into clear sections. Each non-goal should have a brief
rationale — not just "we won't do X" but "we won't do X because Y."
The design philosophy section should be short and sharp — 2-3 principles
that a team member could recite without looking at the document.
-->

> **Status — rebuilt from evidence 2026-08-02.** Rewritten from the shipping code, the release history, and the accepted ADRs, replacing a version whose in-scope definition was built around MDM-pushed silent provisioning and a Tauri core — neither of which exists. It describes **v0.4.0** (released 2026-08-02); the underlying code survey was taken one release earlier at v0.3.2 (commit `e0bf0c3`), and every fact affected by the difference has been reconciled forward. Product status is **DOGFOODING** — live on one organization (ENAC), sixteen of sixteen layers applied, not offered outside and not generally available.
>
> **Version note.** **v0.4.0** was cut on 2026-08-02 during this rebuild: it lands the connections bridge (Settings and wizard step 6 render the organization's declared services with their real shared-store connection state via a new `cc connections --json` verb) and moves the embedded helper to `cc 2.2.0`. That work is in scope and now shipped; nothing else in this document changes.
>
> This is not a plan for a future release. Everything under "In Scope" already exists in a signed, notarized binary. Where something is genuinely unfinished it is named as such.

## In Scope (as shipped at v0.4.0)

Scope here is stated as the product that exists, because the product exists. It is **macOS-only**, distributed as a signed and notarized arm64 DMG that a person installs themselves, and it carries its own pinned, independently notarized `cc` helper inside the bundle so that the app and the intelligence it renders can never drift apart.

**The User app.**

- A menu-bar tray: aviator glyph plus one of twelve badge tokens, refreshed on a single 300-second timer and on launch and on popover open. Right-click gives `Sync now`, `What changed`, `Settings…`, `Quit`.
- A popover organized in the person's language: `YOUR COPILOTS`, `AVAILABLE TO JOIN` (with per-row Join), `SHARED WITH YOUR TEAM`, `YOUR ACCOUNTS`.
- A nine-step first-run setup: welcome, connect GitHub, detect, what you're getting, departments, Your connections, Your projects, Set up, verify. GitHub sign-in is a browser device flow; the app's data model has no field that can hold a token.
- A Settings window rendering four components (Knowledge, CLI, Claude, Codex) by four tiers (Foundation, Organization, Department, Personal), each row resolving to ready / needs setup / needs attention / not joined / could not check, with the visible repository name and on-disk path.
- Project aftercare: five CLI-authored triage categories with per-project detail, `Run in Codex` / `Run in Claude Code` opening a real Terminal session at the project with the CLI-generated prompt, plus copy-prompt, copy-handoff, finish-safely, and check-again routes.
- A "What changed" view with an explicit empty state, because "nothing changed" must be a claim the app can actually back.

**The Admin app.** Sixteen surfaces across two families — eleven onboarding (orientation, prerequisites, contacts, connect GitHub, describe your organization, integrations, secret store, review setup, organization setup, setup check, done) and five governance (add a department, someone left, connect the shared store, org setup, analytics). It is the same seven source files as the User app plus two more, compiled with a build flag; the User build cannot reach it. Every existence and idempotency decision is made by a deterministic bash engine using check-then-act, with `gh` and `jq` vendored into the bundle so the operator's machine needs neither.

**The setup transaction.** All deterministic preflight — including a nine-state git-history classifier — runs before any irreversible GitHub write. Only a merge-base-proven fast-forward is auto-repaired; the other eight states route to a person. Apply asserts `HEAD == target` as a postcondition, distinguishes "already at target" from "fast-forwarded", and threads a run-scoped completed-actions ledger through every exit path. Held and blocked items are surfaced honestly rather than being conflated with failure or omitted.

**The contract seam.** Nine verb families are consumed: `doctor`, `auth` (status / login / grant), `layers` (and join), `freshness` (including all-projects), `update` (including fan-out and per-project), `onboard` (personal and organization scope), `workspace` (nine subverbs), and — as of v0.4.0 — `connections`. The schema gate decodes only `schema_version` before trusting any other field and requires an exact major match per verb. The compatibility pin is declared in a file that ships in every release directory.

**Release and recovery.** Developer ID signing, notarization, stapling, and Gatekeeper verification, gated by a suite that includes a 138-scenario smoke harness, a sixteen-row eight-history-state topology gate driven against the packaged binary rather than a mock, a vendored-helper checksum verification, a release gate that rejects a signed app missing its Apple Events entitlement or purpose string, and a headless setup-transaction proof. Every release since 0.2.0 carries an explicit rollback paragraph naming the prior signed DMG, under the standing rule that release tags are immutable and a defective build is superseded rather than moved.

**If only three things could ship, they are:** the versioned CLI JSON contract with its fail-closed gate, the nine-step wizard that gets a non-technical person to a working sixteen-layer machine without a terminal, and the preflighted setup transaction that makes it safe to let that wizard touch a real GitHub organization.

## Non-Goals

Each of these is a decision, not an omission, and each carries the reason it was decided.

- **No resolution, health, signature, merge, or wipe logic in the app.** *Rationale:* it would duplicate a hardened pipeline and create a second source of truth — and the app's would be the one that can be wrong. If a decision requires computing ecosystem state, it belongs in the CLI. The test is simple: if Control Tower vanished, the CLI would still be correct.
- **No Windows.** *Rationale:* **formally out of scope.** The shipping app is native macOS SwiftUI/AppKit; a native SwiftUI app is macOS-specific by construction. The Windows work that exists — the platform shims, the WiX/MSI packaging, the Task Scheduler design, the ten Windows fitness tests — lives entirely inside the retired Rust tree, was authored and tested on a Mac with no Windows toolchain, and **has never once been run on Windows**. The parity document that describes it is a record of a plan for an implementation that no longer ships.
- **No MDM, and no device management of any kind.** *Rationale:* **dropped completely as a mechanism**, ratified in the CSE alignment decisions and carried into the soul. No `.mobileconfig` generation, no Jamf/Kandji/Intune flow, no forced or managed configuration domain, no fleet dashboard as the admin's center of gravity, no forced-key deprovision. Entitlement and deployment are GitHub repository access. Install is a self-install of a signed, notarized DMG. Security-sensitive configuration is rehomed to compiled-in trust roots plus signed, inherited organization and foundation configuration — nothing security-critical comes from user-editable local config. Offboarding is revoking the person's GitHub access and rotating shared-store tokens, with the honest accepted residual that content already on a departed person's disk is not remotely wiped. This is acceptable for the target of small, trusted organizations and is stated rather than hidden.
- **No `publish` verb.** *Rationale:* **formally deferred** per ADR-008 (Accepted 2026-07-31). The author-side push of a writable organization or department tier is not implemented and nothing scheduled builds it. The full design — auto-merge non-overlapping edits, then a plain-language keep-yours / keep-theirs / keep-both chooser, then park-and-escalate, with all merge computation CLI-side and the app rendering only the choice — is preserved as a design record. Its schema file still exists on disk. No document in this repository may list it as an existing verb. The safe interim substitute for the case that actually arises — elevating a project-level skill, agent, or command to a shared tier — is a documented manual copy-commit-push into the tier repository's own working directory, never a symlink.
- **No `repair` verb.** *Rationale:* **formally deferred** per the same ADR. History remediation lives inside `cc onboard`'s own routing, where the eight-state classifier already routes fast-forwardable rows to an in-onboard repair and every review state to the owner. A parallel verb would duplicate ancestry-proof logic and create two sources of truth for the same git facts. If repair semantics are ever needed outside onboard's routing, that requires a new ADR rather than an assumption from old contract prose.
- **No `resolve` or `deprovision` in the app.** *Rationale:* both have schemas on disk and both were implemented in the retired Rust tree, but the shipping app calls neither. `resolve` is a CLI diagnostic the app has no rendering need for; a deprovision UI presupposes the device-management model that was dropped. Their presence in `schemas/` is contract history, not an app surface.
- **No Tauri, Rust core, or web UI as the shipping stack.** *Rationale:* **retired**. The release pipeline never invokes `cargo`, `tauri build`, or `npm`; it compiles Swift and signs the result. The version drift is the proof — everything else moved to 0.3.2 while the Rust manifest sat at 0.2.4. **The tree stays on disk** as read-only historical reference and is not proposed for removal in this pass; it still supplies the app icon and the bundle identifier. Two things it also still holds are named below as open gaps.
- **No telemetry, no fleet dashboard, no analytics emitter.** *Rationale:* the entire telemetry design — the content-free schema, the non-reversible machine identifier, the four fitness tests guarding it — exists only in the retired Rust tree. The native Admin app has an Analytics governance surface with a toggle and no emitter behind it. Nothing is collected today, so nothing about a fleet can be claimed today. This is a real limitation on what can be measured and it is stated as one in `20-success-metrics.md` rather than papered over with targets.
- **No in-app self-update.** *Rationale:* the updater, its signature verification, and its staged-bundle rollback are Rust-tree machinery that the native rebuild did not carry over. People update by installing a DMG, and roll back by reinstalling the prior signed DMG — which is exactly what every release note instructs. This is a smaller, more auditable surface than an auto-updater, and re-adding one would need to clear the same bar the rest of the security posture does.
- **No syncing of the products and projects people build.** *Rationale:* the load-bearing distinction of the whole model. Control Tower orchestrates the tooling you build *with* — Knowledge Copilot, CLI Copilot, and the Claude/Codex instruction layer — across the four tiers. A product or project carries its own knowledge, skills, agents, and integrations inside its own repository, standardized by the instruction layer when you work in it. It is never a Control Tower sync layer, and there is no "department project" in the model.
- **No second GitHub organization, and no practice organization.** *Rationale:* the confidentiality boundary is the repository, not the organization (ADR-001), so a second organization buys nothing and doubles the administration. And the dogfood runs directly against the real organization (ADR-003) because it is the hardest case — publisher and first consumer at once — so a throwaway rehearsal would have tested an easier problem than the one that matters.
- **No zero-touch install.** *Rationale:* the self-install path is the critical path, not a fallback. A zero-touch path presupposes device management, and designing around one would have let the hard case — a person installing this themselves and understanding what happened — stay unsolved.
- **No monetization, in any form.** *Rationale:* pure open source, free forever. No paid tier, no enterprise SKU, no hosted service, no closed component. Openness is not a pricing decision here; it is the security guarantee. An always-on agent that holds a live token and materializes executable-adjacent content is trustworthy only if it is fully auditable, so a paywalled or closed component would directly undermine the product's reason to exist. Success is adoption, trust, and reliability — never revenue.
- **Not designed for the reliable power user.** *Rationale:* the developer who is comfortable in a terminal keeps using the CLI directly and must not be broken by this product, but the experience is designed for the person who cannot. Optimizing for the power user would quietly reintroduce the terminal step that the essence forbids.

### The line: "helping do X" versus "doing X for them"

The escalation model *is* this line, made concrete. The app **does X for** the person when X is reversible and they could not reasonably judge it — re-running the pipeline, fast-forwarding a clean checkout, re-materializing a tree the CLI owns. It **hands X to whoever holds the authority** when authority is required — an organization-level decision belongs to whoever administers the organization, not to whoever is nearest the menu bar. It **asks the person** only when they are the sole competent actor about their own material — the one GitHub sign-in, a dirty working tree that only they can decide about, a project only they can approve as theirs. It never asks anyone to make a decision they have no basis to make, and it never notifies anyone about something they cannot act on.

## Anti-Features

Things that would make the product worse. Say no even when asked, and especially when the request is reasonable — every one of these arrives as a sensible convenience.

- **Any bypass flag** (`--force`, `--skip-verify`) or a lower-bar mode to unstick a machine. The entire safety claim is that the agent runs the same pipeline with zero bypass flags. One backdoor and the security review that gates all adoption ends in a no.
- **A "make it healthy anyway" override.** It fabricates exactly the false-green the fail-closed states exist to prevent, and it converts an honest unknown into a confident lie.
- **Offline health scoring** so the icon "still works" when the CLI cannot run. A computed verdict is a second and wrong source of truth. Waiting-for-network is a real state and a better answer.
- **Reading security-sensitive configuration from user preferences** — an update feed location, a mirror, a trust setting. A preference write becomes remote code execution.
- **Screen-scraping human CLI output** instead of parsing the contract. A misread `fail` as `pass` shows green over red; it is the single highest integration risk in the product.
- **A watchdog that always resurrects the app.** Restarting after a clean quit is disrespectful; restarting a crashing build is a crash loop. Crash-only or nothing.
- **Raw git or VCS output shown to a non-technical person.** Conflict markers, detached-HEAD warnings, non-fast-forward rejections. Collaborative tiers are the product's own doing, so the failures they introduce are the product's to absorb.
- **Any path that lets personal content reach a shared tier by accident** — one remote for everything, filter-on-push, a warning dialog as the only guard. The leak is irreversible, so it must be impossible by construction rather than discouraged by discipline.
- **Percentages, countdowns, or time estimates in setup.** An estimate is a computed promise the app cannot keep honestly. Name the phase.
- **A celebratory success state** — green fill, checkmark, confetti. Silence is the success state. Healthy is the absence of signal, never a reward.
- **Status carried by color alone.** Shape encodes first, color second, sentence always. A blended color blob is a blur, not a fact.
- **A chat surface or any model-driven judgment inside the app.** It is a tower, not the pilot.
- **Real-time or per-minute content refresh.** Cadence is the correct model; a manual sync-now covers the rare urgent case. Constant refresh burns battery and attention for no essential gain.

## Constraints

**Technical.**

- Native macOS SwiftUI/AppKit, ~22,650 lines of Swift compiled by `swiftc` into three executables from an explicit source list — never a glob, so a file cannot silently join a build.
- Developer ID distribution, not the Mac App Store: the sandbox forbids spawning the CLI the whole product exists to render.
- Userland only. Per-user everything. No admin rights, no privileged helper, no writable shared state.
- The CLI is invoked by absolute, translocation-safe path, resolved from the bundle first and never from `$PATH` — both because a bare name would be ambiguous with an unrelated tool and because the pinned helper must win over any machine-installed one.
- The versioned JSON contract is the entire safety boundary. Schema drift is a silent security bypass, so the gate is per-verb, exact-major, and fail-closed; the incident that proved this necessary took down every Claude Code prompt on a machine.
- The child process gets a private temporary directory and a marker environment variable, so helper extraction cannot be starved by a crowded shared temp directory (a real cold-start stall fixed in 0.2.4).
- arm64 only today.

**Organizational and business.**

- One person builds, signs, and releases this. Signing custody is a named single point, and a two-of-N custody model is designed but not staffed. This is the binding constraint on release cadence and on what can be maintained, and it is why "as little app as possible" is a survival principle rather than an aesthetic.
- Open source is a requirement and the go-to-market, not goodwill. It is what makes the security argument work.
- Never-destroy is a hard line: freely re-materialize what the CLI owns and re-clone disposable mirrors; never touch a human-owned working tree. Every visible checkout is human-owned.

**Privacy and compliance.**

- Secrets never enter inheritance content or any git repository, at any tier, public or private. Inheritance content carries a reference to a secret's name and how to acquire it, never a value. Git is a distribution and history mechanism, not a trust boundary.
- Credentials live in the per-user OS keychain and/or a tier-scoped shared store whose endpoint arrives via inherited organization configuration. The endpoint is not a secret; access stays gated by the person's own GitHub team membership. Git push credentials are always per-user and never shared-store material.
- Sync is pull-only and downward. Personal content never flows upward automatically; any upward publication is a separate, human-invoked, distinctly-credentialed action.
- Nothing is collected. There is no emitter, so there is no telemetry privacy surface to argue about today — and any future emitter inherits the requirement that a personal item name be un-emittable by construction.

## Design Philosophy

Three principles, in priority order, under one inviolable constraint. The order is settled so that a live argument does not have to relitigate it. Above all three sits **security posture is inherited and never weakened** — not a principle to trade against, a constraint.

### Principle 1: Parse, never compute

Control Tower calls CLI verbs and renders the result. It holds no resolution, sync, signature, or wipe logic of its own. **The test:** does this require the app to compute ecosystem state? If yes, it belongs in the CLI. Stop. This is the cheapest gate and it kills the most bad ideas. It is also absolute: when routing tempts the app to compute so that nobody has to be bothered, honesty wins and the app escalates instead.

### Principle 2: Route by actor-competence times reversibility, not by event class

For every event, ask who is the sole competent actor and whether the action is reversible. Auto-act on reversible things the person cannot judge; route to whoever holds authority what they cannot action; ask the person only about non-deferrable decisions on their own material. **The test:** who is the sole competent actor, and is the action reversible? Proximity to the menu bar is not competence, and a notification someone cannot act on is a regression, because it spends the credibility of the one alert that matters.

### Principle 3: As little app as possible

One signed binary. No daemon, no fallback loop, no heavy framework, no bypass flags. Trust comes from *less* surface for an enterprise review to audit, not more. **The test:** does this add audit surface, and does the essential job survive without it? If both, cut it. The one exception the priority order permits: an *added honest state* is worth its surface, because a false green is the single outcome worse than more UI.

## Integration Boundaries

| Will NOT Integrate With | Reason |
|------------------------|--------|
| MDM platforms (Jamf, Kandji, Intune) in any capacity | Dropped completely as a mechanism. Entitlement and deployment are GitHub repository access; install is a self-install. Re-adding MDM would be a future re-architecture as an optional adapter, never a dormant seam kept alive now |
| GitHub as a system of record beyond what the CLI already does | It surfaces and supervises; it does not become a second place where access lives. Repository access is the entitlement, and GitHub remains its owner |
| HR or directory systems | Not a directory product. It reads what it needs at the moment it needs it and owns no org structure |
| Arbitrary third-party update feeds or mirrors set by users | Trust roots are compiled-in code, not configuration. A user-editable trust surface is a supply-chain attack with extra steps |
| The Mac App Store | The sandbox forbids spawning the CLI the app exists to render |
| Any cloud or remote-execution backend | It bridges the local machine's CLI. It is not a remote session service, and adding one would move the trust boundary off the person's own device |
| Any closed, paid, or hosted component | Openness is the security guarantee. A closed component invalidates the audit argument that makes the whole thing acceptable |
| Chat or model APIs from inside the app | It renders the CLI's verdict; it never generates one |

## Future Considerations

Nothing in this table is scheduled. Each row states what it is, why it is out of scope now, and what would have to be true first. There are no dates anywhere in this document by design.

| Feature | Why Out of Scope Now | Conditions for Future Inclusion |
|---------|---------------------|--------------------------------|
| **The V-5 cold-laptop proof** | Not a feature — the last outstanding validation. A second machine starting with an empty keychain must onboard, clone both mirrors, and resolve every service with no hand-copied secret and no `.env` | It is next in sequence and owner-gated. Until it passes, the claim "a new machine can join unaided" is a design intent, not a demonstrated fact |
| **Publicizing the two private foundation repositories** | Deliberately last, because it is irreversible and high blast radius | Gated on a scrub and on the credential rotation that the recorded history exposure requires. Not to be attempted out of order |
| **Porting the fitness suite to scan the shipping Swift** | The forty architectural fitness tests all scan the retired Rust tree, and the CI job that runs them is disabled behind a repository variable. They are a historical guarantee about an implementation that no longer ships | Named as open gap **G-1**. The six invariants are today upheld by architecture and review, plus the shell release gates — **not** by automatically-enforced properties of the shipping binary. Any document claiming otherwise is wrong. Closing this means rewriting the tests against `native/*.swift` and re-enabling the job |
| **The crash-only launchd watchdog** | The invariant describes it, the packaging assets exist, and a fitness test guards the plist — but the shipping Swift app does not install or manage it | Named as open gap **G-2**. The invariant stands as the design position; the absence is the current state. Closing it means implementing it natively, still crash-only and never always-restart |
| **A first-class `repair` verb** | Deferred per ADR-008; repair semantics live inside onboard's routing and a parallel verb would create two sources of truth for the same git facts | A need that genuinely falls outside onboard's routing — for example repairing a materialized tree independent of ecosystem setup — proposed and ratified as a new ADR that supersedes ADR-008 |
| **The `publish` path for writable tiers** | Deferred per ADR-008. It is a distinct and larger workstream: conflict rendering, leak scan, tier-scoped credentials. The multi-writer authoring loop has still never been run with more than one writer | Two real authors exercising the loop, plus a ratified answer to which content classes skip straight to escalation rather than offering a choice. Until then, elevation is the documented manual copy-commit-push path |
| **Telemetry and any fleet view** | No emitter exists in the shipping app; the design lives in the retired tree | An organization that actually needs it, plus a schema in which a personal item name is un-emittable by construction, plus genuine per-organization opt-in. Absent all three, collecting nothing is the correct posture |
| **In-app self-update** | Not carried over from the retired tree. Install-a-DMG and roll-back-a-DMG is smaller and more auditable | A signature and rollback design that clears the same bar as the rest of the security posture, and a maintenance model that can sustain an update feed |
| **Personal-key sync across a person's own machines** | Accepted as a real need and still unsolved — it is the origin pain (hand-copying `.env` between two machines) in its last unfixed form | A carrier that reconciles with the per-user on-device key model without becoming a shared-credential store. The V-5 proof is the first evidence that will inform it |
| **Windows** | Formally out of scope, not merely deferred. The shipping app is macOS-native, and the Windows tree describes a retired implementation that never ran on Windows | A deliberate decision to build a second native client, with its own design pass. Nothing in the current tree is a head start on that; treating it as one would be the mistake |
| **A third-party IT operator running Admin mode** | Not a feature, but the largest untested assumption in the product. Admin mode has stood up a real sixteen-layer organization — run by the person who wrote it, on his own organization | One real operator, unaided, with only the app and the documentation. Everything Admin-side is a hypothesis until then, and should be written and read that way |
