# Copilot Control Tower — Design Package Status

> **Status — rebuilt from evidence 2026-08-02.** Describes **v0.4.0** (released 2026-08-02). Product status is **DOGFOODING** — live on one organization (ENAC), sixteen of sixteen layers applied, not offered to outside organizations and not generally available.
>
> **Purpose:** the resume point. Pick this up in a new conversation to see exactly where the design package stands.
> **How to use it:** tell Claude *"Check `docs/product-design/TODO-DESIGN-PACKAGE.md` for where I left off."*

---

## What happened on 2026-08-02

The entire package was **rebuilt from evidence**. The prior version was not incomplete — it was *inaccurate*, which is worse, because it read as authoritative. Written between 2026-07-08 and 2026-07-17, it described a Tauri/Rust product with live MDM deployment, and a README claiming the build had not started. By 2026-08-02 the real product was ~22,650 lines of native SwiftUI/AppKit shipping at v0.4.0 with eight version lines and seven retained signed releases behind it.

Every one of the fifteen facilitated documents was re-derived from the shipping code, the release history, the accepted ADRs, and the ratified decision records. `SOUL.md` was rebuilt and ratified as **v2.0**. Ten contradicted documents outside this package were repaired in the same pass.

**Read this before trusting any older design artifact in this repository.** The lesson the package now carries in its own bones: an honest marked gap always beats a confident fabrication.

---

## Owner answers ratified 2026-08-02

These govern every document in the package and are not to be re-litigated without a new ratification.

| # | Decision |
|---|---|
| A-1 | **Audience**, in weight order: the owner's future self and session continuity; non-technical buyers and evaluators; teams and organizations looking for new ways to transform their organization. Explicitly *not* open-source contributors, and *not* a developer receiving a handoff |
| A-2 | **Essence remains DEMOCRATIZATION** — a technical person's superpowers in a non-technical person's hands. Organizations are the buyer; the individual is where value lands. Reframing the essence around organizational transformation was explicitly rejected |
| A-3 | **Status is DOGFOODING, live on one org.** Never "the build has not started" (false), never general availability. Remaining: the V-5 cold-laptop proof, then publicize, in that order because the second is irreversible |
| A-4 | **Tauri** is retired as the shipping stack but **its code tree stays on disk — no code is removed**. **Windows** is formally out of scope. **MDM** is dropped completely as a mechanism |
| A-5 | **The invariant-enforcement gap is documented honestly as a named open item**, not fixed in this pass and not quietly reframed away |
| — | **Priority order ratified:** say-only-what-you-can-prove **>** parse-never-compute > plain-words-or-nothing > route-by-competence × reversibility > as-little-app, under the inviolable security-posture-never-weakened. Honesty was promoted *above* invariant #1 because on 2026-07-31 the app satisfied parse-never-compute and still lied |
| — | **Pure OSS, free forever** reaffirmed as absolute, re-put specifically in light of the newly-named buyer and organization audiences. Openness *is* the security guarantee |

---

## Status summary

| Status | Count |
|--------|-------|
| DONE (rebuilt from evidence 2026-08-02) | 15 facilitated documents + `SOUL.md` |
| NOT STARTED | 0 |
| IN PROGRESS | 0 |

Both checkpoints **PASSED**. Phase 6 is **COMPLETE by a different route than the template anticipated** — see below.

---

## Phase 1: Discovery

**Design Foundation Checkpoint requirement — vision + scope + success metrics exist: MET**

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 1 | `00-overview/00-vision.md` | DONE | Problem, users, forces map, JTBD, magic moment, non-goals, Capabilities & Essence (the upstream input `SOUL.md` formalises) |
| 2 | `00-overview/10-scope-and-non-goals.md` | DONE | In-scope at v0.4.0, non-goals with rationale, anti-features, constraints. Windows out of scope; MDM dropped; `publish`/`repair` deferred per ADR-008 |
| 3 | `00-overview/20-success-metrics.md` | DONE | Rewritten to remove targets nothing in the product could produce. Two honest gaps marked: nobody at ENAC beyond the owner is known to run it, and no baseline study exists for a time-savings claim |

## Phase 2: Research & Service Design

**Design Foundation Checkpoint requirement — an interview plus journeys/JTBD/moments exist: MET**

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 4 | `01-research/10-interviews/01-interview-self.md` | DONE | ⚠️ **Sole surviving primary owner testimony.** The cited `scratchpad/interview-ground-truth.md` no longer exists — gitignored, never committed, absent from every ref. Eight verbatim 2026-07-06 quotes are preserved here unchanged; everything else is labelled inference or decision-of-record |
| 5 | `02-service-design/30-jtbd.md` | DONE | Primary job, supporting jobs, ranking, competing solutions. Key reframe: the product is not hired to manage an ecosystem, it is hired to make an unverifiable system trustworthy enough to be left alone by someone who cannot check it |
| 6 | `02-service-design/20-journey-maps.md` | DONE | Personas: **Bob** (non-technical adopter, primary, grounded), **Earl** (org owner/admin — run once by the author, the largest untested bet), **Pablo** (author who publishes upstream, observed continuously) |
| 7 | `02-service-design/40-moments-that-matter.md` | DONE | MTM-1 the account of what just happened · MTM-2 the day nothing happens (the false-green class) · MTM-3 the stop that is not a failure |
| 8 | `02-service-design/10-service-blueprint.md` | DONE | Nine backstage seams (B1–B9) and four failure points, drawn from real incidents |

**── CHECKPOINT: Design Foundation — PASSED ──**

- [x] Vision, scope and success metrics complete (#1–3)
- [x] At least one completed interview (#4)
- [x] Journeys, JTBD and Moments That Matter complete (#5–7)

---

## SOUL.md — RATIFIED v2.0

| Document | Status | Notes |
|----------|--------|-------|
| [`../../SOUL.md`](../../SOUL.md) (project root — deliberately not in `docs/`) | DONE | **RATIFIED v2.0, 2026-08-02.** Five principles each carrying a rejection test; ten named anti-patterns, four newly dated to real incidents; a six-gate Feature Filter with thirty case-law rows; settled priority order. §6 states what the quality bar does **not** enforce, because a soul claiming a bar the product does not meet is itself a Comfortable Lie |

The four newly named and dated anti-patterns: **The Comfortable Lie** (2026-07-31 — an apply reported it stopped "before changing anything" after two repositories had already been created and seeded) · **The Quiet Bulldozer** (2026-07-27 — 12,537 lines reconcile-deleted through a symlink and pushed to origin) · **The Contract That Drifted** (2026-07-28 — a `component:`→`product:` field rename turned an optional hook into total prompt rejection) · **The Machine Talking To Itself** (a **live** leak at `control-tower-tray.swift:1375`).

---

## Phase 3: Requirements

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 9 | `03-requirements/10-user-stories.md` | DONE | 35 stories — Bob 19, Earl 8, Pablo-author 8. 26 SHIPPED / 6 PARTIAL / 3 NOT SHIPPED. Unfinished work concentrates entirely in the author's *writable* direction |
| 10 | `03-requirements/20-use-cases-and-scenarios.md` | DONE | Scenarios drawn from real events, not hypotheticals — the ENAC live run and the three incidents above |
| 11 | `03-requirements/30-acceptance-criteria.md` | DONE | 53 criteria. **10 have automated verification that gates a release; 18 have a harness that does not gate one; 1 rests on the single live run; 24 rest on code review alone.** Two recorded NOT MET: no rollback instruction shipped in v0.4.0, and no contrast audit exists |

## Phase 4: Experience Design

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 12 | `04-experience-design/50-ux-design.md` | DONE | Real IA: one menu-bar glyph opening a six-region popover, a nine-step setup window, and a read-only Settings window, alongside the separately-built 16-surface Admin app |
| 13 | `04-experience-design/60-ui-design.md` | DONE | Named direction **Quiet Instrument** (in the two-app "Native Calm" family); named anti-direction **The Alert Machine**. Tokens documented from real `NSColor` semantics, not invented |
| 14 | `04-experience-design/70-copy-voice.md` | DONE | Voice: a calm operator who refuses to guess. 17 jargon leaks catalogued with file:line, each paired with a marked recommendation, none fixed in code |

## Phase 5: Design Challenge

| # | Document | Status | Notes |
|---|----------|--------|-------|
| 15 | `05-design-challenge/00-brief.md` | DONE | Eight critical views. Primary evaluation standard: *does this change make it easier or harder to say something unprovable?* Plus 13 instant rejections |

**── CHECKPOINT: Design Complete — PASSED ──**

- [x] All requirements documents complete (#9–11)
- [x] UX, UI and copy documents complete (#12–14)
- [x] Design challenge brief written and approved (#15)
- [x] Critical views list confirmed (eight)

---

## Phase 6: Prototype — COMPLETE, by a different route

**The prior tracker's most misleading claim was here.** It pointed a resumer at an unstarted Figma / Design-Spec / Storybook / Next.js choice. None of that happened, and none of it is going to.

The prototype phase was satisfied by **building the real product**. The output is the shipping native SwiftUI/AppKit application at v0.4.0 — three signed executables, notarized and released — and its design of record is the native design triad, not a template document:

| Output | Path |
|--------|------|
| Experience architecture | [`../03-design/ui-ux/control-tower-native-experience-architecture.md`](../03-design/ui-ux/control-tower-native-experience-architecture.md) |
| Interaction spec | [`../03-design/ui-ux/control-tower-native-interaction-spec.md`](../03-design/ui-ux/control-tower-native-interaction-spec.md) |
| Visual system | [`../03-design/ui-ux/control-tower-native-visual-system.md`](../03-design/ui-ux/control-tower-native-visual-system.md) |

The `06-prototype/` folder is retained as an unused template artifact. Do not resume there.

---

## Open items — carried honestly

None of these block the package. All are real and none were fixed during the documentation rebuild, because the owner scoped that pass to documentation and forbade code changes.

**Full write-up with severity, root cause and proposed fix for each: [`../04-validation/audit-2026-08-02-findings.md`](../04-validation/audit-2026-08-02-findings.md).** That document is the durable record — it ranks these Critical → Low, adds the ones that are not design-package concerns (accessibility, repository hygiene, the closed security audit), and preserves the raw evidence the rebuild was derived from.

| ID | Item |
|----|------|
| **G-1** | **The invariants are stated but not enforced.** All 40 `fitness_*.rs` tests scan `src-tauri/src/**` — the retired Rust tree — and cannot see one line of the shipping Swift. The CI job that runs them is disabled behind `vars.RELEASE_CI_ENABLED`. Porting the suite to scan `native/` is open work |
| **G-2** | **Invariant #2's `launchd` crash-only watchdog is not implemented** in the shipping Swift app; it exists only in the retired Rust tree |
| **G-3** | Phase 6 never happened as the template describes — recorded above rather than left as a false resume point |
| — | **V-5 cold-laptop proof** — a two-machine onboarding run against an empty keychain, proving the experience holds for someone who is not the owner |
| — | **Publicize** — making the supporting foundation repos public, gated on a credential rotation their prior private history requires. Irreversible, so it follows V-5 |
| — | **Live jargon leak** at `control-tower-tray.swift:1375` (and VoiceOver at `:1387`) — raw layer ids and the CLI's raw severity enum on the most-read surface, while the ratified plain labels sit 25 lines earlier, bypassed. Structurally, the ban is unenforceable in the app because CLI-authored `detail` prose passes straight through under invariant #1; the fix belongs in the `cc` contract |
| — | `control-tower-logo.svg` is not bundled, so the wizard hero falls back to `building.2` — contradicting the ratified brand rule |
| — | Two divergent badge vocabularies (tray uses 12 tokens, Settings maintains a separate 5-state set); `update` and `spinner` are defined but unreachable |
| — | No rollback instruction in the v0.4.0 changelog; no contrast audit; no light/dark Dynamic Type proof; no keyboard pass |
| — | **The primary persona has never been validated.** Bob is grounded in design but no non-technical adopter outside the owner is known to have completed setup unaided. This is the single highest-value unmeasured fact about the product |

---

## Reference

| File | Purpose |
|------|---------|
| [`../../SOUL.md`](../../SOUL.md) | The decision instrument. Run any proposed feature through its six-gate Feature Filter before building |
| [`../../CLAUDE.md`](../../CLAUDE.md) | The six invariants — the product's spine |
| `01-research/10-interviews/00-interview-template.md` | Generic interview template — copy and rename for additional interviews |
| `06-prototype/README.md` | Unused template artifact, retained. See Phase 6 above |
