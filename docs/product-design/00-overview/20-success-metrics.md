# Success Metrics

<!--
FACILITATION GUIDE — Service Designer
======================================
This document defines how we know if the product is working.
Metrics must be OUTCOME-based, not feature-based.

Bad: "Users can do X" (that's a feature)
Good: "Users accomplish Y that they couldn't before" (that's an outcome)

PREREQUISITE: 00-vision.md and 10-scope-and-non-goals.md must be
completed first.

CONVERSATION FLOW:
1. Define what success looks like for the user
2. Define what success looks like for the business
3. Define leading indicators (early signals things are working)
4. Define failure indicators (signals things are NOT working)
5. Define quantitative metrics (measurable targets by category)
6. Define qualitative metrics (per-persona survey targets)
7. Define operational efficiency targets (current vs. target state)
8. Define ecosystem health metrics (cross-product flow)
9. Define design quality metrics (principles-based indicators)

QUESTIONS TO ASK:

## Round 1: User Success
- "If a user has been using this for a month and it's working
  perfectly, what has changed for them?"
- "What would they be able to do that they couldn't before?"
- "How would you measure whether the core value proposition is real?"
- "What does 'good enough' look like for an AI-assisted output?"

## Round 2: Business Success
- "What does success look like for you as the product owner?"
- "Is this a product you'll sell, use internally, or both?"
- "What's the business model — SaaS, per-use, internal tool?"
- "What would make you say 'this was worth building'?"

## Round 3: Leading Indicators
- "What are the earliest signs that this product is working?"
- "What user behavior would tell you they trust the product?"
- "What would indicate the product is finding the right problems to solve?"

## Round 4: Failure Indicators
- "What would tell you this product is NOT working?"
- "What's the worst outcome — the thing that would make you shut it down?"
- "What does 'garbage in, garbage out' look like here?"

## Round 5: Quantitative Metrics
- "For each category (performance, adoption, quality, business), what
  specific targets would you commit to?"
- "How would you measure each of these? What's the data source?"
- "What's the performance target for the core AI-assisted workflow?
  What's good enough vs. excellent?"
- "What adoption rate in the first 90 days would tell you this is working?"

## Round 6: Qualitative Metrics (Per Persona)
- "If you surveyed the primary user after 30 days, what would they say
  if the product is working? What percentage agreement would satisfy you?"
- "What would a secondary persona say about the quality of what surfaces?"
- "What would an admin or configurator say about the ease of setup?"

## Round 7: Operational Efficiency Targets
- "What does the current state look like — how long does each part
  of the process take today?"
- "What's the target state? What time savings are realistic?"
- "Where is the biggest time sink in the current process?
  Is that the right thing to optimize first?"
- Frame as: Current State → Target State for each workflow step.

## Round 8: Ecosystem Health Metrics
- "If this product feeds data to other tools, how do you measure
  whether that handoff is healthy?"
- "What would indicate AI-generated outputs are being used
  (not just computed and ignored)?"
- "How do you track whether outputs flow into real decisions
  vs. getting abandoned?"

## Round 9: Design Quality Metrics
- "What design principles govern this product? How would you know
  if those principles are being honored or violated?"
- "What would a feature-creep warning look like in the metrics?"
- "What are the quality indicators that tell you the product is staying
  true to its purpose?"

SYNTHESIS:
Present metrics as outcomes, not features. Each metric should be
observable and measurable, even if qualitative. Avoid vanity metrics
(page views, signups) — focus on whether the product is doing its job.
Present as structured tables: Quantitative (with targets and measurement),
Qualitative (per persona with survey language and % targets),
Operational Efficiency (current state vs. target state),
Ecosystem Health, and Design Quality.
-->

> **Status — rebuilt from evidence 2026-08-02.** Rewritten to remove targets that nothing in the product could ever produce, replacing a version built around fleet dashboards, MDM push rates, and survey percentages for personas nobody has surveyed. It describes **v0.4.0** (released 2026-08-02); the underlying code survey was taken one release earlier at v0.3.2 (commit `e0bf0c3`), and every fact affected by the difference has been reconciled forward. Product status is **DOGFOODING** — live on one organization (ENAC), sixteen of sixteen layers applied live, not offered outside and not generally available.

> **The measurement constraint, stated first because it governs everything.** **There is no telemetry emitter in the shipping app.** The entire telemetry design — the content-free schema, the non-reversible machine identifier, the fleet view — lives in the retired Rust tree and was not carried over. The native Admin app has an Analytics surface with a toggle and nothing behind it. Consequently: **no fleet-scale, adoption-rate, or population metric in this document is measurable today, and none is stated as if it were.** What *is* measurable is the release gate suite (automated, binary, runs on every release), the setup transaction's own completed-actions ledger, the defect record in the changelog, and direct observation of a one-organization dogfood. Every metric below is tagged with which of those it comes from, or marked as not-yet-measurable with the condition that would change that.

## North Star — adoption through ease, with a floor of honesty

The owner's own framing: *if it is easy for people to use, people will adopt it, and that is the sign of success.* Adoption is not one axis among several; it is the axis, and **ease is its cause**. Everything else — trust, reliability, the entire supervision apparatus — exists to *earn* the unattended running that makes adoption effortless.

But adoption sits on a floor that is not a target and never will be: **the product must never claim a state it cannot prove.** A false green is not a metric that gets optimized toward zero. It is a defect class that invalidates the product, because the one thing being sold is that the person no longer has to check.

## User Outcomes

What has actually changed for the people using it, stated as outcomes rather than features.

- **A person can reach the whole ecosystem without being technical.** Before, Knowledge Copilot and CLI Copilot were effectively single-user inside the organization, because reaching them required terminal fluency. Now the path is a double-click, a browser sign-in, and a setup that names what it will do before doing it. `Evidence: OBSERVED barrier / DEMONSTRATED at one organization` — the sixteen-layer topology applied live, sixteen of sixteen.
- **The person who was the sync layer is no longer the sync layer.** A change made once upstream reaches an entitled machine on cadence rather than because someone remembered. `Evidence: OBSERVED pain / DEMONSTRATED single-machine mechanism` — the multi-writer, multi-machine case is what the V-5 cold-laptop proof is for and is not yet demonstrated.
- **Setup tells the truth about itself.** A person is shown the classification of every repository before anything irreversible happens, and afterwards is told exactly what was done — held items and blocked items included, rather than conflated with failure or omitted. `Evidence: SHIPPED and gated` — the completed-actions ledger threads every exit path, and "nothing changed" is only a legal claim on an empty ledger.
- **Recovery has a dignified path.** Every release since 0.2.1 ships an explicit rollback instruction naming the prior signed DMG, under an immutable-tag rule. A person who breaks something can get back without understanding why. `Evidence: SHIPPED` — seven signed releases retained on disk.
- **What has NOT yet changed:** whether a person other than the author can complete this unaided. <!-- TODO: confirm how many people at ENAC beyond the owner are running Control Tower today, and whether any of them completed first-run setup with no assistance. This is the single highest-value unmeasured fact about the product. -->

## Business Outcomes

Under the pure-open-source model there is no revenue metric, by design. "Worth building" resolves to three things, in this order.

- **Trust that survives inspection.** The audit argument is the product's permission slip: one signed binary, no daemon, no bypass flags, compiled-in trust roots, a pinned and independently notarized helper, and a fail-closed contract gate. The measurable version of this is not a survey — it is whether the security properties hold under adversarial reading. `Measurable today via:` the release gate suite plus code review. `Not measurable today:` whether an external security team accepts it, because none has reviewed it.
- **Reliability that shows up as absence.** The right shape of success is a changelog that stops needing a Fixed section about honesty defects. `Measurable today via:` the changelog's own defect record, read as a series (see Failure Indicators).
- **Adoption beyond one organization.** The honest current number is one, and the two things standing between here and a second are named: the V-5 cold-laptop proof and the publicize step. `Not measurable today` — and stating an adoption target before a second organization exists would be inventing a number.

## Leading Indicators

The earliest real signals, all observable without telemetry.

- **The V-5 cold-laptop proof passes.** A second machine, empty keychain, no hand-copied secret, no `.env`, onboards and resolves every service. This is the first evidence that the product works for someone who is not the machine it was built on. It is the single most informative outstanding test.
- **A setup completes for a person who did not build it, unaided.** The specific thing to watch is whether they had to ask a question that the interface should have answered — every such question is a design defect with a name.
- **The owner stops fixing things by hand.** The clearest proxy available: how often the author has to reach into a machine outside the app to make the ecosystem correct. Each intervention is an unshipped feature or an unshipped honest state.
- **Release gates keep passing without being loosened.** The gate suite is the product's conscience. A gate that gets relaxed to let a release through is a leading indicator pointing the wrong way, and it will show up in the git history of the scripts long before it shows up in a defect.
- **Held and blocked states get used rather than worked around.** A person hitting a hold and following the offered route — rather than asking how to force it — is the routing model working.

## Failure Indicators

These are not hypothetical. Each is drawn from something that actually happened, which is why they are the right list.

- **A false ready.** The product claims a layer, a project, or a machine is set up when it is not. This has happened: through v0.2.3 a GitHub repository or a hidden mirror counted as an installed layer, so a person could see a green Personal result with no visible repository anywhere on their disk (fixed in 0.2.4 under ADR-005). This is the worst class in the product; it makes the icon a liar and everything downstream worthless.
- **Something the person owned was destroyed.** This has happened: a materialize target pointed at a human-owned authoring checkout, and one routine update reconcile-deleted 12,537 lines of organization content in a single commit, which a backup job then pushed. Never-destroy is not a slogan; this is what it costs when the structural separation is not maintained.
- **A contract mismatch takes the ecosystem down.** This has happened: a manifest field rename shipped while the resolver still filtered the old field, the organization overlay vanished, and a hook exited non-zero — so Claude Code rejected every prompt on the machine. The durable countermeasures are the per-verb schema gate, the fail-open policy for optional hooks, and the release gate that drives the packaged binary rather than a mock.
- **A component reports a capability it does not have.** This has happened: a phantom secret-store provisioner could report a store as configured when it was not (closed in `cc 2.2.0`). Any report of readiness that is not backed by a verification the app can point at is this defect wearing a different hat.
- **A support answer becomes "just force it."** There is no force. If the honest answer to a stuck machine ever becomes a bypass, the safety claim has already cracked — the answer arriving is the signal, not the flag being added.
- **The interrupt count climbs.** People being asked about things they cannot judge, or notified about things they cannot act on. It burns the credibility of the one message that matters.
- **The app computes something.** Any resolution, health, signature, merge, or wipe logic appearing in Swift. This is a design-level failure regardless of what any metric says, and it is the one failure that no amount of good outcomes redeems.

## Quantitative Metrics

Only metrics with a real data source appear here. Where a category has no honest metric today, that is stated rather than filled in.

| Category | Metric | Target | Measurement |
|----------|--------|--------|-------------|
| **Correctness** | Release gate suite passes end to end before any release is signed | 100%, non-negotiable — a failing gate blocks the release rather than being waived | The packaging pipeline: 138-scenario smoke harness, headless detect, app bundle test, schema compatibility gate, notarization order test, watchdog plist lint, headless setup-transaction proof |
| **Correctness** | The sixteen-row, eight-history-state topology gate runs against the **packaged** helper binary, never a mock, and asserts zero mutation plus source/packaged parity | 100% pass, every release | `scripts/tests/test_packaged_cc_topology_contract.sh`; also run in both placeholder and release modes by the vendored-helper verifier |
| **Correctness** | Vendored helper integrity: checksum matches the pin, notarization intact, signature not re-signed by packaging | 100% pass, every release | `verify-vendored-cc.sh --release` |
| **Correctness** | A signed app missing its Apple Events entitlement or user-facing purpose string is rejected | 100% — the gate exists precisely because a silently-missing entitlement produces a feature that appears to do nothing | `verify-user-automation.sh` |
| **Honesty** | Setup transactions where a blocked preflight row produced any GitHub mutation | Zero. All deterministic preflight runs before any irreversible write, so a blocked row yields no repositories at all rather than a partial set | The completed-actions ledger and the `HEAD == target` postcondition, exercised by the topology gate |
| **Honesty** | Layers claimed as ready without a visible repository, a manifest connection, a synchronization, a non-empty resolution, and a post-apply verification | Zero — readiness requires all of them (ADR-005) | The onboard report, rendered rather than computed by the app |
| **Delivery** | Releases carrying an explicit, tested rollback path naming the prior signed artifact | 100% since 0.2.1 | The changelog and the retained signed releases on disk |
| **Scope of the live install** | Layers applied live on the dogfooded organization | 16 of 16 — reached in Phase 7 | The initiative's own acceptance record |
| **Adoption** | People and organizations running it | Not measurable, and honestly small: one organization. There is no emitter and no registry, so any number here would be invented | `Not measurable today.` Would require either genuine per-organization opt-in telemetry with an un-emittable-personal-name schema, or a deliberate manual count |
| **Performance** | Time from an upstream change to it landing on an entitled machine | Bounded by the 300-second status poll and the sync cadence — a deliberate design parameter, not a target to shrink. Real-time refresh is explicitly the wrong model | The poll timer is a fixed constant in the tray controller; a manual `Sync now` covers the urgent case |
| **Quality** | Honesty defects per release, read as a trend | Trending to zero. The 0.2.4, 0.3.0, 0.3.2, and 0.4.0 releases each closed at least one — a false-ready, a misclassified history state, a conflated held item, a phantom provisioner | The changelog's Fixed sections, read as a series rather than individually |

## Qualitative Metrics (User Surveys)

**No survey has been run.** Stating agreement percentages for populations that do not exist would be exactly the failure this rebuild is correcting. What follows is the language to test *when* there is someone to ask, and an honest note on the current sample size for each.

### The non-technical person (post-setup)

Current sample: <!-- TODO: confirm whether anyone other than the owner has completed first-run setup on the dogfooded organization, and if so how many. Until this is answered, every statement below is design intent, not evidence. -->

- *"I got the whole thing working and never opened a terminal."* — the core promise; anything less than near-universal agreement means the essence has failed.
- *"It told me what it was going to do before it did it, and afterwards it told me what it actually did."*
- *"It only ever asks me about my own stuff."*
- *"When something was wrong, one sentence told me what and who fixes it."*
- Anti-signal to watch for above all others: *"I wasn't sure whether it had actually worked."* Uncertainty after a green result is the false-ready defect being felt rather than measured.

### The IT or admin operator (post-organization-standup)

Current sample: **one, and it is the person who wrote it.** Admin mode has stood a real sixteen-layer organization up end to end, but no third-party operator has ever touched it. Every line below measures a bet.

- *"I stood the organization up from the app and the documentation alone — I never hand-edited YAML or crafted a configuration profile."*
- *"Before it changed anything, I could see exactly what it was going to create, download, or leave alone."*
- *"When it stopped, it stopped cleanly and told me why, instead of leaving half an organization behind."*

### The owner (post-release)

Current sample: one, continuously, and the only genuinely longitudinal evidence the product has.

- *"I am no longer the sync layer."* — the origin job.
- *"I did not have to reach past the app to make the ecosystem correct."* — the sharpest available proxy for whether the product is finished enough to be left alone.
- *"The release gate caught it before I did."* — the sign the conscience is working.

## Operational Efficiency Targets

Framed as toil class rather than duration; there are no time estimates in this package by rule, and no baseline study of the manual path exists to support one.

| Workflow Step | Current State | Target State |
|---------------|---------------|--------------|
| A person joining the ecosystem | Impossible without terminal fluency, so in practice it did not happen — the layers stayed single-user | Double-click, browser sign-in, nine named steps, no terminal, no YAML, no config file |
| Getting the full topology onto a machine | Hand-cloned repository by repository by whoever knew the layout | One planned, preflighted transaction covering four components at four tiers, with the visible folder for each shown before it is created |
| Knowing whether a machine is correct | Ask the one person who could tell, or find out when something broke | One glanceable honest state, refreshed by re-running the real pipeline rather than by remembering the last answer |
| Getting a change from one machine to every machine | The author carried it by hand, machine by machine, and remembered or did not | Authored once, pulled on cadence by everyone entitled, with personal work untouched |
| Standing up an organization | Hand-created repositories, hand-set access, hand-written configuration | Guided surfaces over a deterministic engine that checks before it acts, with a setup check at the end |
| Recovering from a bad release | Improvise | Reinstall the named prior signed DMG; tags are immutable and a defective build is superseded, never moved |
| Elevating a project's skill or agent to the whole organization | Undefined, and once catastrophically improvised via a symlink | A documented copy-commit-push into the tier repository's own working directory, with the symlink path explicitly forbidden |

**Toil removed per cycle:** the entire terminal, YAML, and hand-provisioning surface for the person, and the entire hand-created-repository surface for the operator. <!-- TODO: if a quantified time-savings claim is ever needed for a business case, it requires a baseline study of the manual path that has never been run. Do not estimate it. -->

## Ecosystem Health Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Personal content reaching a shared or public tier | Zero, structurally — no personal-holding path has an upward push credential, and personal and shared live in separate trees with separate remotes | Architecture and review. `Not automatically enforced against the shipping Swift` — see the design-quality note below |
| Secrets committed to any tier's repository, public or private | Zero. Inheritance content carries a secret's name and acquisition method, never a value; git is never a secrets carrier at any tier | Review, plus the shared-store model where the endpoint arrives via inherited configuration and is not itself a secret |
| A human-owned working tree modified by the app | Zero. Every visible checkout is human-owned; a clean checkout may be reused or fast-forwarded, a dirty one is never touched | The history classifier's routing, and the never-destroy compensation rule of report-rather-than-delete |
| Materialized content matching the CLI-computed winning layer | Exact match, always — because the app renders and never computes, any divergence means the app has started computing | Would be shown directly by the CLI's own explain output. `Currently limited:` the live manifest lacks a per-layer static source path, so that explain output returns an empty item set — a tracked gap in the CLI, not in the app |
| Optional hook failures breaking the harness | Zero. Hook shims are transport fail-open by policy, codified in the compatibility pin after the incident where a hook exit code rejected every prompt | The compatibility file's declared hook policy and its bounded internal timeout |

## Design Quality Metrics

Reviewed at every release as a design check, not as a dashboard.

| Indicator | Measure |
|-----------|---------|
| **Parse-never-compute held** | Zero resolution, health, signature, merge, or wipe logic in the Swift. Upheld by architecture and code review |
| **Single binary held** | One signed binary per face, built from an explicit source list rather than a glob. No daemon, no fallback loop |
| **No bypass exists** | No force, no skip-verify, no lower-bar mode anywhere in the codebase. The absence is the metric |
| **Honest states used correctly** | Unreadable, out-of-range, and could-not-check are real rendered states rather than fallbacks to optimism. Missing security fields fail closed |
| **Interrupts stay rare** | The set of things the person is asked about stays small and stays about their own material |
| **No estimate, no percentage, no countdown** | Setup progress is named by phase only. An estimate is a promise the app cannot keep |
| **Feature creep flagged** | Any proposal that adds judgment surface, audit surface, or a second source of truth is caught at review by the vision document's regression-trigger table |
| **Enforcement gap named, not hidden** | **The six invariants are upheld by architecture, review, and the shell release gates — not by automatically-enforced properties of the shipping binary.** The forty architectural fitness tests all scan the retired Rust tree and cannot see a line of the shipping Swift, and the CI job that runs them is disabled behind a repository variable. This is open gap **G-1**. A second gap, **G-2**, is that the crash-only watchdog the invariants describe exists only in that same retired tree. No document may claim otherwise, and neither gap is closed by this documentation pass |

## Acceptance Criteria (Three-Stakeholder)

### For Users

*"I got the whole thing working and never opened a terminal. It showed me what it was going to do before it did it, and told me afterwards what it actually did. It asks me about my own stuff and nothing else. Most days it says nothing at all, and I have learned that silence means it is fine — because the one time something was wrong, it told me plainly and it was right."*

### For the Business

*"It is pure open source and free forever, and that is the strategy rather than a compromise: openness is what makes an always-on agent acceptable to an organization at all. It is worth having built when the honesty defects stop appearing in the changelog, when a machine that is not mine can join without me, and when the person who used to carry this by hand no longer has to. There is no revenue line here and there never will be."*

### For the Ecosystem

*"People get the tooling their repository access already says they should have, with nobody hand-provisioning a machine. A change authored once reaches everyone entitled to it, on cadence, without touching anything anyone owns. Nothing personal ever moves upward. And when the system cannot prove something is true, it says so — which is the only reason anyone should be willing to leave it running."*
