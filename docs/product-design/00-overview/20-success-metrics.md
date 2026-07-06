# Success Metrics

> **Provenance.** Grounded synthesis, **re-grounded in the owner interview of 2026-07-06**
> (`01-research/10-interviews/01-interview-self.md`). The *definition of done* (`prd.md` §1, §12) and
> the red-team findings supply the outcome shape; **quantitative thresholds have no field baseline
> yet**, so every number below is a **provisional target** derived from the product's own logic and
> tagged `(PROVISIONAL)`. Prerequisites: `00-vision.md`, `10-scope-and-non-goals.md`.
>
> **Business-model note (DECIDED, Pablo 2026-07-06):** Control Tower is **pure OSS, free forever — no
> monetization.** Success is measured in **adoption + trust + reliability**, never revenue.
>
> **Honest evidence caveat.** Almost every number below is a target for a *future* state, and much of
> the surface it measures is untested: **Admin/IT-operator metrics are HYPOTHESIS** (no real IT
> operator has touched Admin mode), **multi-writer authoring metrics are MODEL-IN-HEAD** (never run
> with >1 writer), and **enterprise-scale figures are ASPIRATION**. Only Claude Copilot's value to a
> team is TESTED, and the non-technical-can't-reach-it barrier is OBSERVED. Do not let a provisional
> number downstream masquerade as a measured result — read the stamp on each section.

## North Star — Adoption Through Ease

> The owner's own definition, verbatim in spirit: **"If it's easy for people to use, people will
> adopt it, and that is the sign of success."** Adoption is not one axis among several — it is *the*
> success signal, and **ease is its leading cause.** Everything else (trust, reliability,
> observability) exists to *earn* the unattended running that makes adoption effortless.

| North-star signal | What it means | Measurement | Evidence stamp |
|-------------------|---------------|-------------|----------------|
| **Live machines / fleets running the ecosystem** | The headline OSS adoption count — unbounded, no ceiling | Count of machines reporting an honest terminal state over time | **OBSERVED barrier / ASPIRATION scale** |
| **Ease → adoption: reached without help** | People adopt *because it was easy* — no terminal, no hand-holding, no support ticket | Share of onboardings that reach a working partner with zero technical assistance | **OBSERVED** (the barrier is real; the removal is the bet) |
| **"Set once, never think about it"** | An authorized change made once lands everywhere on cadence without the author babysitting it | Share of upstream changes that propagate to all target machines within one cadence, no manual carry | **MODEL-IN-HEAD** (multi-writer never run) |
| **Non-technical reach** | People who could *never* reach Knowledge/CLI Copilot now use them | Count of non-Pablo users actively reaching those layers via Control Tower | **OBSERVED** (single-user today) |
| **Pulled away from generic chat** | Every conversation goes to the solution-oriented ecosystem, not the Claude app / ChatGPT / Gemini | Share of usage routed through the ecosystem vs. generic chat fallback | **HYPOTHESIS** |

The metrics below remain valid, but they are **subordinate to adoption**: they describe the *trust
and reliability that make effortless adoption possible*, not the goal itself.

## User Outcomes

When Control Tower is working, after a month:

- **Bob** has a working, team-scoped Copilot partner he provisioned with (at most) three answers — or
  zero on a managed fleet — and has *not once* had to open a terminal, edit YAML, or make a technical
  decision he had no basis for. The machine stays healed without his attention, and the only things
  it ever asks him about are his own data (commit dirty WIP; the one sign-in).
- **IT** can look at a dashboard and know which machines are healthy, stuck, behind, or need re-auth —
  the observability that did not exist before — and every safety-relevant event has reached a live
  channel rather than dying in a local log.
- **Nobody** is running a version that a shipped security fix was supposed to close: a
  security-shadowing override was auto-suspended, not left to a notification.

## Business Outcomes
> **Adoption-first (see North Star).** "Business" here means adoption + trust + reliability under the
> pure-OSS model — never revenue. The single headline is **live machines/fleets**, whose cause is
> **ease of use.**

Success for the product owner (`architecture.md` §1; `prd.md` §12 exit):

- Enterprises adopt the whole Copilot ecosystem **without friction** — the CLI-shaped barrier is gone
  for non-technical staff, and the hand-craft barrier is gone for IT.
- The always-on agent is *demonstrably safer* than a human running `copilot update` by hand — every
  pull visible, verified, policy-bounded, auditable — and this survives an enterprise security review
  (open source + reproducible builds + two-of-N signing).
- **All 25 Critical/High red-team findings are closed**, the CLI `--json` contract test is green, and
  a test Mac silently self-provisions from an MDM push and reports fleet health.
- **The project is a healthy open-source adoption driver** — because Control Tower is pure OSS (free
  forever, no paid tier), "worth building" is judged by ecosystem adoption (fleets/machines live),
  the trust it earns (security reviews passed, the audit basis holding), and contribution health —
  not by revenue.

<!-- DECIDED (Pablo, 2026-07-06): Business model = pure OSS, no monetization. "Worth building" is
     measured by ecosystem adoption (fleets/machines live) + trust + reliability, NOT a commercial
     tier and NOT revenue. Open source is both the security requirement and the go-to-market. -->

## Leading Indicators
Earliest signs it's working:

- **Silent-provision success rate climbs** — managed pushes complete to Healthy (or an *honest*
  Waiting-for-network / IT-config-incomplete), not false-Healthy.
- **IT trusts the dashboard enough to act on it** — an admin resolves a stuck machine *because the
  dashboard flagged it*, not because Bob called.
- **Escalations land on the right actor** — held-majors go to IT, security-shadows auto-resolve, and
  Bob's notification volume stays near zero (a sign routing-by-competence is holding).
- **The `--json` contract test stays green across CLI releases** — the safety boundary isn't drifting.

## Failure Indicators
Signals it is NOT working (and the "shut it down" outcomes):

- **False-Healthy in the field** — a machine reports Healthy while foundation-only or mis-provisioned
  (the A-C1 / H7 / H12 class). This is the worst outcome: it makes the icon a liar and the dashboard
  worthless.
- **A security fix that didn't take** — a vulnerable overriding version kept winning because a signal
  depended on Bob seeing a notification (the C3 class).
- **The IT channel is a no-op** — safety escalations reached no one because they were gated behind
  off-by-default analytics (the C5 class).
- **Bob-notification fatigue** — Bob is asked things he can't action, and starts ignoring the app,
  which then misses the one alert that matters.
- **The app computed something** — any resolution/health/signature/wipe logic creeping into Rust; a
  second source of truth. This is a design-level failure regardless of metrics.

## Quantitative Metrics

| Category | Metric | Target | Measurement |
|----------|--------|--------|-------------|
| **Performance** | Freshness poll → status refresh latency | **< 2 s** <!-- PROVISIONAL: the render is a parse of already-fetched --json, not a network op — the menu bar must feel instant; revisit with instrumented p95 --> | app instrumentation; poll cadence sync ~6h / doctor ~1h / freshness ~15m (`prd.md` B5) |
| **Performance** | Silent managed first-run: push → Healthy/honest-holding-state | **≥ 95% reach Healthy without human touch; p90 ≤ 10 min** <!-- PROVISIONAL: silent provision is the core promise, so success must be high; wall-clock is network-bound (clone + materialize) and falls back to an honest holding state past the bound, so the invariant is honesty not speed; revisit with fleet baseline --> | wizard checkpoint timestamps (`architecture.md` §4) |
| **Adoption** | Managed machines that reach a *true* terminal state (Healthy / Waiting-for-network / IT-config-incomplete) vs. stuck | **≥ 99% reach a true state; ~0% false-Healthy (hard invariant, not a number to optimize)** <!-- PROVISIONAL: honest-state coverage should approach 100% since even Waiting-for-network counts; the ~0% false-Healthy is invariant #1 — any false-Healthy is a Critical regression, not a tuning target --> | fleet dashboard (G3) |
| **Adoption** | Fleet on the current locked SHA within one sync cadence of publish | **≥ 90%** <!-- PROVISIONAL: one sync cadence (~6h) after publish; slack for asleep/offline/metered machines that catch up on the next poll; revisit against real version-skew data --> | version-skew panel (G3) |
| **Quality** | Auto-heal success: `warn`/healable `fail` resolved without human action | **≥ 90% of known-parseable healable failures** <!-- PROVISIONAL: self-heal for the known warn/healable-fail classes is the always-on promise, so it must be high; unknown/non-parseable classes correctly escalate rather than auto-act and are excluded from the denominator; revisit with doctor→repair outcome data --> | `doctor`→`repair` outcomes over the auto-act lane (`architecture.md` §9) |
| **Quality** | Security-shadow auto-suspend coverage (vulnerable override never wins silently) | 100% (invariant — any miss is a Critical regression) | escalation-router audit log (F2) |
| **Quality** | `--json` contract test pass rate across CLI releases | 100% green gate | CI contract test in the `copilot` repo (A6) |
| **Adoption / trust** | Orgs/fleets stood up from Admin mode + docs alone (no hand-YAML, no support escalation) | **≥ 90% of setups complete unaided** <!-- PROVISIONAL: business model is pure OSS, so this is an *adoption/enablement* metric, not revenue — it measures whether the enabler (Admin mode) actually removes hand-craft; the headline OSS metric (count of live fleets/machines) grows unbounded and has no fixed ceiling; revisit with real setup telemetry --> | Admin-mode seed-generator + preflight completions |

## Qualitative Metrics (User Surveys)

### Bob — non-technical employee (Post-Onboarding)

- *"I got a working AI partner without doing anything technical."* — Target: **≥ 90% agree** <!-- PROVISIONAL: this is the core Bob promise and the hero moment — it should score very high or the product has failed its primary persona; revisit with real post-onboarding survey -->
- *"It stays working on its own; it only asks me about my own stuff."* — Target: **≥ 85% agree** <!-- PROVISIONAL: slightly lower bar than first light because it accrues over a month of real use and depends on fleet conditions; revisit with cohort data -->
- Anti-signal to watch: *"I got notifications I didn't understand and started ignoring them."*

### IT / Admin operator (Post-Setup)
> `> **Evidence: HYPOTHESIS**` — no real IT operator has run Admin mode, deployed a fleet, or seen the
> dashboard. Every target in this block measures a bet, not an observation. Treat as design intent
> until an actual operator is in the room.

- *"I stood up and deployed the ecosystem from the guided tool and docs alone — I never hand-edited
  YAML or crafted an MDM profile by hand."* — Target: **≥ 90% agree** <!-- PROVISIONAL: Admin mode is the enabler of Bob's silent first light, so removing hand-craft is its whole reason to exist; revisit with real IT-operator survey -->
- *"I can tell a healthy Mac from a stuck one at a glance."* — Target: **≥ 95% agree** <!-- PROVISIONAL: this closes the ecosystem's named observability gap and rests on honest states (a hard invariant), so it should score near-universal; revisit with IT survey -->
- *"When something needed my authority (a held-major, a policy), it came to me — not to the employee."*

### Pablo / ecosystem owner (Post-Security-Review)

- *"An enterprise security team audited the always-on agent and accepted it as safer than manual
  `copilot update`."* — Target: **100% of formal security reviews reach an accept/adopt outcome** <!-- PROVISIONAL: trust is a core success axis under the pure-OSS model and the audit basis (open source + reproducible builds + two-of-N signing) is engineered to pass; a rejected review is a signal to fix the product, so the target is 100%; revisit as real reviews accumulate -->
- *"No shipped security fix was defeated by a personal override or an unseen notification."* — Target: 100%.

## Operational Efficiency Targets

<!-- Current state = today's CLI-shaped path (reference/ecosystem-use-cases.md UC1; architecture §8).
     No time estimates per project rule — framed as toil class, not hours. -->

| Workflow Step | Current State | Target State |
|---------------|---------------|--------------|
| Employee onboarding | Run a shell script, confirm department at a prompt, read `copilot update` output — requires a terminal Bob doesn't have | One double-click (or a silent MDM push); ≤3 questions unmanaged, 0 managed |
| Org standup (seed authoring) | Hand-write `ecosystem.yml`, hand-create per-dept repos, hand-set CODEOWNERS/branch-protection | Guided seed generator + repo/access scaffolding; PR opened for you (H1–H2) |
| MDM deployment | Craft a `.mobileconfig` by hand per MDM vendor | One generated artifact (managed keys + login-item + notifications payloads) → upload once (H4) |
| Rollout validation | Discover a typo/missing key *after* the fleet is broken (false-Healthy) | Preflight red/green report *before* pushing (H5) |
| Fleet health check | No way to tell healthy from bricked — wait for a call | Dashboard: healthy / stuck / behind / needs-auth at a glance (G3) |
| Staying synced | Manual `copilot update`; prunes and security trailers swallowed by cron | Always-on self-heal; prunes of recently-used items surfaced; security fixes auto-acted |

**Total toil removed per cycle:** the entire terminal/YAML/hand-MDM surface for Bob *and* IT — the
CLI-shaped adoption barrier the product exists to remove. <!-- TODO: if a quantified time-savings
claim is needed for a business case, a baseline study of the current manual path is required. -->

## Ecosystem Health Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Safety escalations that reach a live IT channel | 100% (mandatory `AdminContact`; on by default for managed machines) | IT channel receipt vs. emitted safety signals (F3; fixes C5) |
| Telemetry PII leakage | 0 personal item names emittable *by construction* | schema review; usage emits only CLI-verified {org,dept,foundation} items (G2; B-H5) |
| Deprovision effectiveness for a leaver (online) | Access revoked on next online `copilot update` even if the app is trashed | server-side token revocation + MDM-run `deprovision` (E3; A-C4) — honest boundary: offline machine can't be wiped, guarantee is "no secret materialized" |
| Materialized content matches CLI-computed winning layer | 100% (the app renders, never computes) | provenance diff vs. `copilot resolve --explain --json` |

## Design Quality Metrics

| Indicator | Measure |
|-----------|---------|
| **Parse-never-compute held** | Zero resolution/health/signature/wipe logic in the app codebase — a code-review gate, checked every release |
| **Single-process held** | Exactly one signed binary; no headless daemon, no in-app fallback loop; `KeepAlive` never `true` |
| **Route-by-competence held** | Every escalation traces to auto-act / escalate-IT / ask-Bob by the matrix; Bob-facing notification count trends toward zero |
| **Security never weakened** | No `--skip-verify` / `--force` path exists; security keys read only from the forced/managed domain — CI entitlement + preference lint |
| **As-little-app-as-possible** | Feature-creep warning: any new capability that adds resolution/judgment surface, or an auditability burden, is flagged at review |
| **Honest states** | Zero false-Healthy incidents in the field; Waiting-for-network / IT-config-incomplete used correctly |

## Acceptance Criteria (Three-Stakeholder)

### For Users
Bob: *"I had a working partner from one click, it never made me be technical, and it only ever
interrupts me about my own data."*

### For the Business
Pablo / ENAC: *"Control Tower is pure OSS, free forever — and that is the strategy: enterprises adopt
the ecosystem without friction, the always-on agent passed a security review as safer-than-manual,
and all 25 Critical/High findings are closed. Success shows up as **adoption (live fleets/machines),
trust (reviews passed, audit basis holding), and reliability (honest states, self-heal)** — never
revenue."*
<!-- DECIDED (Pablo, 2026-07-06): pure-OSS adoption driver. The headline business metric is adoption
     count (unbounded, no ceiling); the adoption/trust/reliability rows above carry the provisional
     targets. No revenue metric exists by design. -->

### For the Ecosystem
IT / fleet: *"I deployed from Admin mode + docs alone, I can see the whole fleet's health, every
escalation reaches me, and offboarding is reliable — the observability gap the ecosystem named is
closed."*
