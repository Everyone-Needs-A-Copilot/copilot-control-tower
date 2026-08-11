> **Evidence appendix — captured 2026-08-02.** A per-document staleness audit of the repository's documentation *as it stood before the rebuild*, recording what each file claimed and how far it had drifted from the shipping product. Every document it marks CONTRADICTED or DRIFTED was subsequently rewritten in commit `c70b66e`, so this file describes the **pre-rebuild** state and is retained as the record of what went wrong, not as a description of the repository today. Readable summary: [`audit-2026-08-02-findings.md`](audit-2026-08-02-findings.md).

---

# Documentation Audit — Copilot Control Tower

Audit date: 2026-08-02. Scope: root docs, `SOUL.md`, `docs/product-design/**`, and `docs/00-overview/` through `docs/10-reference/` (excluding `docs/40-initiatives/`, which is out of scope for this pass but was consulted for ground-truth cross-checks). This is a documentation-claims catalogue, not a code-verification pass — a parallel agent is establishing code ground truth separately.

## 0. Headline finding

The single biggest, highest-value finding is a **large, unresolved documentation fork around the Tauri-to-native-SwiftUI pivot**. `CLAUDE.md` (2026-07-31), `docs/START-HERE.md`, and the three native-app design docs (`docs/03-design/control-tower-native-experience-architecture.md`, `control-tower-interaction-spec.md`, `control-tower-visual-system.md`, all 2026-07-17) correctly state the app is native macOS SwiftUI/AppKit and that "this supersedes the prior Tauri v2 / web-UI plan." But several docs that are *supposed to be authoritative* — `README.md`, `docs/01-architecture/architecture.md`, `docs/02-prd/prd.md`, `docs/01-architecture/12-architecture-guiding-principles.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/01-architecture/windows-parity.md`, `docs/03-design/ui-ux/README.md` — still describe Tauri v2/Rust as the current or target stack, in some cases in docs edited *after* the pivot docs landed. A second, smaller fork exists around MDM: `SOUL.md` v1.4 (2026-07-09) and the CSE alignment decisions ratify "MDM is dropped completely" (D4), and most `05-security`/`10-reference` docs have been conformed to that, but `SECURITY.md`, `CONTRIBUTING.md`, `docs/02-prd/prd.md`'s non-goals line, and `docs/03-design/ui-ux/README.md` still reference MDM/Jamf/Kandji/Intune as live mechanisms.

Separately, `README.md`'s "Status: Private / pre-build… the build has not started" is flatly false against `CHANGELOG.md`, which documents releases through **v0.3.2 (2026-08-01)** and a native app with real onboarding transactions, schema versioning, and rollback procedures.

---

## 1. Root docs

| Doc | Last modified | Verdict | Evidence |
|---|---|---|---|
| `README.md` | 2026-07-17 | **CONTRADICTED** | Stack table says "Tauri v2 (Rust core + minimal web UI)… macOS-first (Windows = later re-skin)"; contradicts `CLAUDE.md`'s native SwiftUI/AppKit description. Status line says "Private / pre-build… the build has not started," contradicted by `CHANGELOG.md` (releases through v0.3.2) and `docs/START-HERE.md` ("The app is built and shipped"). MDM-deployable claim also contradicts SOUL v1.4 D4 (MDM dropped). |
| `CLAUDE.md` | 2026-07-31 | **FRESH** | Correctly states native SwiftUI/AppKit, explicitly supersedes the Tauri v2/web-UI plan, correctly reflects the 6 invariants including the deferred-verbs (`repair`/`publish`) and MDM-dropped language. This is the most current, accurate root doc. |
| `AGENTS.md` | 2026-07-30 | **CONTRADICTED** | "Stack: Tauri v2 / Rust / TypeScript / Vite" — one day before `CLAUDE.md`'s 07-31 edit, yet still describes the retired stack. Since this file is read by Codex Copilot as project overview, it actively misinforms an agent about the tech stack. |
| `CHANGELOG.md` | 2026-08-01 | **FRESH** | The most current, most reliable ground-truth document in the repo — chronicles v0.2.0 through v0.3.2 with dated, specific fixes/changes/QA/rollback notes. Useful as the reconciliation anchor for every other doc's staleness. |
| `CONTRIBUTING.md` | 2026-07-07 | **CONTRADICTED** | "Control Tower is a macOS menu-bar app (Tauri v2)…"; Development-setup section asks contributors to install "Rust (stable) + Tauri v2 CLI"; Build section says `tauri build` produces the binary. All contradicted by the shipped native Swift app (`native/*.swift`, `scripts/build-user.command`/`build-admin.command`). Still references `docs/07-contributing/README.md` for dev-environment docs — that path does exist (`docs/07-contributing/README.md`, `release-and-versioning.md`, `publisher-release-runbook.md`, out of this audit's directory scope but present). MDM still named as the sole channel for security config, contradicting SOUL v1.4 D4. |
| `SECURITY.md` | 2026-07-07 | **DRIFTED / stub** | Text says the app has "write access to `.claude/`" and lists "MDM-managed config" among sensitive areas — the MDM framing contradicts SOUL v1.4 D4 (MDM dropped completely, 2026-07-09, two days after this file's last edit). `<!-- TODO: security contact -->` is an unfilled placeholder — no actual reporting channel exists. |
| `SOUL.md` (root) | 2026-07-17 | **FRESH — RATIFIED v1.4** | See §2 below. This is the most carefully maintained document in the repo: it explicitly logs its own revision history, self-corrects prior versions (MDM dropped at v1.4), and is internally consistent. No Tauri/MDM contradictions found in its own text. |

---

## 2. SOUL.md — section-by-section summary (RATIFIED v1.4, 2026-07-09 content, file touched 2026-07-17)

1. **The Job** — the struggling moment is democratization: a non-technical person ("Bob") wants a technical person's AI superpowers without learning YAML/terminal, and trusts an always-on agent to keep the environment ready. Introduces the two consumer psychographics (Bob = safety, Ada the author = power) plus Earl (IT) and Pablo (owner).
2. **The Essence** — soul statement: "gives a non-technical person the AI superpowers of a deeply technical one — safely enough to run unattended." Parse-never-compute is framed as *how* it earns the right to run unattended, not the essence itself. Includes the IS/IS-NOT table, which explicitly states "Control Tower syncs the tooling you build WITH, never the products you build" (D1/D2 CSE alignment).
3. **Design Principles** — three ordered principles: Parse-never-compute > Route-by-competence-×-reversibility > As-little-app, under an inviolable security-never-weakened constraint. Each has a named rejection test.
4. **Anti-Patterns** — six named failure modes (The Second Pilot, The Alert Machine, The Convenience Backdoor, The Copilot of the Copilot, The Ledger That Learns to Bill, The Leak, The Git Error To A Non-Technical Person), each with drift/why/early-warning/line-in-the-sand.
5. **Feature Filter** — four sequential gates (Parse-Not-Compute, Essential-Job, Right-Actor, Trust-Surface) plus a 34-row Case Law table of ratified IN/OUT feature verdicts, the load-bearing reference for `CONTRIBUTING.md`'s feature-rejection table.
6. **Quality Bar** — 8 non-negotiable, checkable release gates (zero resolution/health/signature/wipe logic in-app; one signed binary; no bypass flags; fail-closed icon; escalation-by-competence; silent managed first-run; never-destroy; unemittable personal-item names in telemetry).
7. **Voice & Tone** — the air-traffic-controller character; a "we say / we don't say" table; tone-by-context table.
8. **Success Signals** — positive adoption signals and drift signals (false-Healthy in the field, rising Bob notification volume, a support answer of "just force it," a proposed offline mode, a roadmap line mentioning a paid tier).
9. **Founding Decisions** — 11 numbered founding calls, including pure-OSS/no-monetization, Bob-first, the four inheritance-safety rules (now elevated to CLAUDE.md invariants), and **Founding Decision #11: CSE alignment**, which explicitly states "MDM is dropped completely (D4)."
10. **Evolution** — a versioned changelog (v0.1 → v1.0 → v1.1 → v1.2 → v1.3 → v1.4) recording exactly what changed and why at each ratification.

**Contradiction check against later docs:** SOUL.md itself names no shipping-stack technology (no "Tauri" string anywhere in its body) and its MDM-dropped decision (§9 Founding Decision #11, dated 2026-07-09) is the one that `SECURITY.md`, `CONTRIBUTING.md`, `docs/02-prd/prd.md`'s stray MDM mention, and `docs/03-design/ui-ux/README.md` all still contradict (see Contradictions §6 below). SOUL.md is not itself stale; it is the correct reference the other docs have drifted away from.

**docs/00-overview/soul.md** (2026-07-06, 5 lines) — correctly a pointer stub: "Superseded — the canonical, ratified Soul lives at repo root: SOUL.md." **FRESH** (handled correctly).

---

## 3. `docs/product-design/**` — 15 facilitated documents + TODO-DESIGN-PACKAGE.md

All 15 Phase 1–5 documents carry a banner: *"Superseded framing. This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of 'product' to mean a CSE tool are superseded."* This is correctly self-flagged — these are **DRIFTED-but-labeled**, not silently wrong. Completion state: all are fully filled narrative documents (no stub content), but several retain internal `<!-- TODO -->` markers for genuinely open design questions (counts below are literal `TODO` string occurrences, not defects).

| # | File | Last mod | Completion | Summary |
|---|---|---|---|---|
| 1 | `00-overview/00-vision.md` | 2026-07-17 | Fully filled (2 inline TODOs) | Product overview reframed around "democratization" from the 2026-07-06 owner self-interview; introduces the Bob/Ada/Earl/Pablo persona split and evidence stamps (TESTED/OBSERVED/GROUNDED/HYPOTHESIS). |
| 2 | `00-overview/10-scope-and-non-goals.md` | 2026-07-17 | Fully filled (6 TODOs) | In-scope v1 defined as MDM/Jamf-Intune-pushed silent provisioning (now superseded); adds cadence-based propagation, writable collaborative tiers, personal-layer content, and non-technical merge-conflict resolution as newly-in-scope items from the owner interview. |
| 3 | `00-overview/20-success-metrics.md` | 2026-07-17 | Fully filled (1 TODO) | North-star = adoption-through-ease, not revenue; user/business outcome tables; explicit evidence-honesty caveat that most numbers are provisional/untested. |
| 4 | `01-research/10-interviews/01-interview-self.md` | 2026-07-17 | Fully filled (5 TODOs) | The primary-evidence 2026-07-06 self-interview with Pablo; origin story, the reframe to democratization, current hand-sync pain across two machines. |
| 5 | `02-service-design/10-service-blueprint.md` | 2026-07-17 | Fully filled (0 TODOs) | Frontstage/backstage blueprint across 7 stages (Deploy→Provision→First Partner→Steady-State→Change/Heal→Escalate→Deprovision); flags the writable-tiers-vs-never-destroy tension as MODEL-IN-HEAD (later resolved by `inheritance-and-publish.md`). |
| 6 | `02-service-design/20-journey-maps.md` | 2026-07-17 | Fully filled (3 TODOs) | Five persona journeys (Bob, Ada, Earl, Pablo, Rosa/Dwayne) with staged struggling moments traced to red-team findings. |
| 7 | `02-service-design/30-jtbd.md` | 2026-07-17 | Fully filled (5 TODOs) | Jobs-to-be-done grouped by persona, explicitly framed as democratization/trust/legibility/continuity jobs, never a "compute this for me" job. |
| 8 | `02-service-design/40-moments-that-matter.md` | 2026-07-17 | Fully filled (2 TODOs) | Critical trust-inflection moments (MTM-1 Silent First Light, MTM-6 Leakage Wall, MTM-7 Merge-Conflict, etc.) with current-state/target-state framing. |
| 9 | `03-requirements/10-user-stories.md` | 2026-07-17 | Fully filled (4 TODOs) | User stories by persona (B/A/O/D codes) with inline Given/When/Then acceptance criteria; Bob-first priority basis locked. |
| 10 | `03-requirements/20-use-cases-and-scenarios.md` | 2026-07-17 | Fully filled (1 TODO) | End-to-end scenarios (Silent First Light managed happy path, unmanaged ≤3-question setup, etc.) tied to red-team failure modes as edge cases. |
| 11 | `03-requirements/30-acceptance-criteria.md` | 2026-07-17 | Fully filled (2 TODOs) | Given/When/Then functional criteria (FC-1…) plus hard invariants (false-Healthy rate = 0) stated as non-negotiable, not tunable. |
| 12 | `04-experience-design/50-ux-design.md` | 2026-07-08 | Fully filled (2 TODOs) | Six UX design principles (P1–P6, e.g. "silence is the success state," "the icon cannot lie") each overriding a generic UX convention on purpose; explicitly notes it ignores the design-core.md's superseded dual-process framing. |
| 13 | `04-experience-design/60-ui-design.md` | 2026-07-08 | Fully filled (2 TODOs) | Visual direction "Air-Traffic Instrument" — monochrome-first menu-bar template icon, native-not-branded, silence-as-success visually, holding states get more design attention than Healthy. |
| 14 | `04-experience-design/70-copy-voice.md` | 2026-07-08 | Fully filled (3 TODOs) | Canonical copy source of truth; two registers (Bob-facing plain language vs. IT-facing technical); banned-language list. |
| 15 | `05-design-challenge/00-brief.md` | 2026-07-08 | Fully filled (6 TODOs) | Phase-6 design-challenge mandate; deliberately runs 3 concept directions instead of the PCC template's default 5, because the Soul's constraints would force degenerate options. |
| 16 | `TODO-DESIGN-PACKAGE.md` | 2026-07-07 | Status-tracker, DRIFTED | Says "SOUL.md — RATIFIED v1.3" (root SOUL is now v1.4, ratified 2026-07-09, two days after this file's last edit) and "Phase 6: Prototype — NOT STARTED (deferred — the build phase)." Both are stale: the app has since been built via a completely different path (hand-authored native Swift + a separate `03-design/control-tower-native-experience-architecture.md`/`-interaction-spec.md`/`-visual-system.md` design track), not the Figma/Storybook/Next.js Phase-6 prototype this file still frames as the next step. **DRIFTED** — this file's "where I left off" pickup instructions no longer match how the product actually got built. |

---

## 4. `docs/00-overview/` through `docs/10-reference/` — file-by-file inventory

### `docs/00-overview/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `product-brief.md` | 2026-07-09 | **FRESH** | Democratization framing, two-faces-over-one-binary summary, explicitly states "Entitlement + deployment is GitHub repo access, not device management" — fully conformed to CSE/no-MDM. No Tauri/SwiftUI stack claim either way (stack-neutral). |
| `soul.md` | 2026-07-06 | **FRESH (pointer)** | 5-line stub correctly redirecting to root `SOUL.md`. |

### `docs/01-architecture/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `architecture.md` | 2026-07-27 | **CONTRADICTED** | The hardened, red-team-validated architecture spec; header table still states "Stack: Tauri v2 · Rust core + minimal web UI"; §"P4 — Windows re-skin" line does note "deprioritized pending the native-macOS-app reconciliation," but the primary stack claim was never updated even though this file was touched 10 days *after* the native-pivot design docs landed. |
| `12-architecture-guiding-principles.md` | 2026-07-08 | **CONTRADICTED** | The file `CLAUDE.md`/`AGENTS.md` explicitly direct agents to read "before durable architecture… work"; its System Context still says "Stack: Tauri v2 / Rust / TypeScript / Vite." Actively misdirects technical decision-making today. |
| `admin-standup-contract.md` | 2026-07-24 | **FRESH** | Machine contract for the Admin app's zero-terminal setup transaction; stack-neutral ("the app" language), consistent with the current native build and ADR-004. |
| `cli-contract.md` | 2026-08-02 | **FRESH** | The authoritative `--json`/`flock` CLI contract spec (WS-A); explicitly documents the deferred `repair`/`publish` verbs per ADR-008 and the current `onboard`/`workspace`/`connections` verbs; most recently touched file in the whole repo. |
| `error-taxonomy.md` | 2026-07-09 | **FRESH** | Canonical exit-code/error-category table; explicitly marked as the single source of truth other docs should link to rather than restate. |
| `inheritance-and-publish.md` | 2026-08-01 | **FRESH (design, not yet implemented)** | Ratified writable-inheritance/`copilot publish` conflict-resolution design; consistent with `cli-contract.md`'s "deferred design" framing for `publish`. |
| `schemas/README.md` | 2026-08-02 | **FRESH** | Index of the JSON-Schema files backing the CLI contract; states schemas win over prose on disagreement. |
| `windows-parity.md` | 2026-07-09 | **DRIFTED (self-aware)** | A 229-line-equivalent (actually 129) Windows-re-skin-over-Tauri parity tracker (ADR-M9-001…006, `src-tauri/src/platform/`, Rust `#[cfg(windows)]` code). Carries its own top-of-file "Deprioritization note (reconcile pending)" acknowledging the native macOS pivot, but the entire body still assumes a shared Tauri/Rust core is what Windows will re-skin. Given the app is now native Swift, most of this doc's technical content (Task Scheduler ADRs mapped to Rust `platform::` traits, WiX/MSI packaging plans) may be entirely moot, not merely stale — but this needs code-side confirmation. |
| `workspace-activation-contract.md` | 2026-07-22 | **FRESH** | Project-integration/workspace-activation contract; consistent with current `cc workspace` verbs. |

### `docs/02-prd/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `prd.md` | 2026-07-17 | **CONTRADICTED** | The parallel multi-phase PRD, explicitly named by `README.md`/`CONTRIBUTING.md` as the authoritative build spec; task B1 says "Tauri v2 single-process scaffold"; D4 says "Self-update: Tauri signed-manifest updater"; §Windows says "Five boundary shims over the shared Tauri core." Non-goals line correctly says "device management (entitlement + deployment is GitHub repo access, not MDM)" — so the MDM framing here is actually already correct, but the Tauri framing is not. |

### `docs/03-design/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `admin-agentic-setup.md` | 2026-07-17 | FRESH-ish | Admin org-setup automation engine design (deterministic script + skill), extends the ratified Admin interaction spec. |
| `admin-experience-interaction-design.md` | 2026-07-10 | FRESH-ish | Wireframe-level interaction design for the redesigned 16-surface Admin mode; explicitly "no Swift, no HTML" (design doc only). |
| `admin-experience-service-design.md` | 2026-07-10 | FRESH-ish | Service blueprint + journey narratives for the redesigned Admin mode, post owner-review 2026-07-10. |
| `brand-assets.md` | 2026-07-16 | DRIFTED (minor) | Logo-vs-tray-glyph source-of-truth; 7 Tauri/MDM hits, likely referencing the retired Aviator-era branding docs by name for provenance — not independently verified line-by-line in this pass. |
| `control-tower-admin-flow.md` | 2026-07-17 | FRESH-ish | UXD interaction/IA for Admin mode "drive-the-agent" flow; explicitly reads on the no-MDM CSE alignment decisions. |
| `control-tower-copy-deck.md` | 2026-07-27 | FRESH | Final UX copy for the native macOS app, organized for direct drop-in to `native/*.swift` — explicitly native-app-targeted. |
| `control-tower-interaction-spec.md` | 2026-07-17 | **FRESH** | Native macOS interaction design spec, Stage 2/3; explicitly states "no MDM anything," documents the MDM/managed-fleet framing as deleted (D4), and lists exactly what was removed from the prior Admin sidebar. |
| `control-tower-native-experience-architecture.md` | 2026-07-17 | **FRESH** | Native macOS experience architecture, Stage 1/3; explicitly states "The Tauri-web UI the owner rejected is out; the target is a true native macOS SwiftUI/AppKit app" and "The 'Tauri v2 / Windows re-skin' line in CLAUDE.md is deliberately overridden for this native rebuild" — this is the doc that *originated* the correction later adopted into `CLAUDE.md` itself. |
| `control-tower-visual-system.md` | 2026-07-09 | **FRESH** | Native macOS visual design system, Stage 3/3; consistently "no MDM and no fleet-as-center." |
| `design-core.md` | 2026-07-07 | **FRESH (self-flagged superseded)** | Carries its own banner: "⚠️ SUPERSEDED (process model). The dual-process/daemon design below is superseded by the single-process model in architecture.md." Correctly handled. |
| `design-distribution.md` | 2026-07-17 | **FRESH (self-flagged superseded)** | Carries "This doc predates the hardened architecture.md and the ratified product name… Where this doc and architecture.md conflict, architecture.md wins." 33 Tauri/MDM hits, all inside a doc that explicitly disclaims authority. Correctly handled. |
| `design-integration.md` | 2026-07-07 | **FRESH (self-flagged superseded)** | Same superseded banner as above; also notes it describes a terminal-degrade path superseded by `architecture.md` §6. |
| `ecosystem-adoption-and-repair.md` | 2026-07-24 | **FRESH** | States "implemented for Phase 6 onboarding," `cc onboard` computes, Admin/User apps render — consistent with current model. |
| `integration-auth-research.md` | 2026-07-16 | **FRESH** | RFC 8252 native-app OAuth research; consistent with the current OS-keychain/device-flow credential design. |
| `landing-site.md` | 2026-07-27 | **FRESH** | Design source-of-truth for a deployable org-branded landing/resource site shipped alongside the app. |
| `publisher-setup-visual-spec.md` | 2026-07-09 | **FRESH** | Visual/interaction spec for `Publisher Setup.app`, explicitly targets native SwiftUI. |
| `three-role-journeys.md` | 2026-07-17 | **FRESH-ish** | Service-design review of Publisher/Admin/User end-to-end onboarding; foundation doc for the current Admin/User redesign work. |
| `ui-ux/README.md` | 2026-07-06 | **CONTRADICTED** | Actively directs Product Creation Copilot to design "the MDM-profile generator" and to output a **Figma file + Storybook component library**, and points PCC at `architecture.md` §8 "(Admin mode, MDM & IT enablement)." Contradicts both the MDM-dropped decision (SOUL v1.4 D4) and the actual native-Swift build path — no Figma/Storybook artifacts were the delivery mechanism; the app was hand-built in `native/*.swift`. Still actively referenced by `README.md` and `CONTRIBUTING.md` as the doc to read "before proposing visual/interaction changes." |

### `docs/04-validation/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `redteam-platform.md` | 2026-07-09 | **DRIFTED (historically scoped)** | "Red Team B — Aviator platform/lifecycle failure modes"; explicitly scoped to "the macOS native-app / daemon / supply-chain layer" under the Aviator/Tauri codename; 4 Tauri + 2 MDM hits. Findings likely still conceptually valid (crash-only watchdog, signing, etc.) but never re-run against the native Swift rebuild. |
| `redteam-use-cases.md` | 2026-07-09 | **FRESH-ish** | "Red-Team A — Aviator vs the 12 ecosystem use cases"; app-layer-only scope; 0 Tauri/MDM hits directly, but still under the Aviator codename and pre-CSE-alignment framing. |
| `test-plan.md` | 2026-07-09 | **DRIFTED** | Test & QA strategy; 5 Tauri + 1 MDM hits; predates both the CSE realignment and the native rebuild — unclear whether it was ever re-run against the shipped native app's actual test suite (the `CHANGELOG.md` references its own extensive test counts, e.g. "860/861 tests," that don't obviously trace back to this plan). |

### `docs/05-security/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `credentials-and-boundary.md` | 2026-07-27 | **FRESH** | Ratified credentials-carrier + personal↔shared leakage-wall design; explicitly conformed 2026-07-08 to CSE D4 (MDM dropped), all 8 MDM mentions are correctly contextual ("no MDM in this product," "dropped along with the rest of the MDM surface"). |
| `incident-response.md` | 2026-07-09 | FRESH-ish | Incident-response runbook covering signing-key compromise, malicious content, leaked secrets, compromised update feed. Referenced by `SECURITY.md`. |
| `security-and-trust.md` | 2026-07-09 | **FRESH** | Index/stub pointing to the two STRIDE+DREAD companion docs; explicitly states "Conformed 2026-07-09 to cse-alignment-decisions.md D4: MDM is dropped completely." |
| `signing-custody.md` | 2026-07-08 | FRESH-ish | Two-of-N release-signing custody design; 2 Tauri hits (likely the minisign-updater mechanism description, not independently verified). |
| `threat-model.md` | 2026-07-09 | **DRIFTED** | STRIDE+DREAD app-level threat model; STATUS line still literally says "This is the threat model of the *app itself* (the Tauri binary…)" and contains a live, unresolved Elevation-of-Privilege finding about "unsanitized rendering of CLI-supplied strings in the **Tauri webview**" with mitigation advice about "the framework's default text-escaping path" and "the Tauri IPC command allowlist." A native SwiftUI/AppKit app has no webview and no Tauri IPC bridge — this specific finding and its mitigation are very likely moot as written, though the underlying risk class (untrusted CLI-string rendering) probably still needs a native-equivalent finding. Most other content (MDM-dropped conformance, deprovision residual) is correctly current. |

### `docs/06-deployment/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `admin-first-two-machine-setup-runbook.md` | 2026-07-27 | **FRESH** | Operator runbook for establishing an org from one Mac then enrolling a second as a user; 0 Tauri/MDM hits. |
| `admin-prerequisites.md` | 2026-07-23 | **FRESH** | Prerequisites + exact GitHub access needed before Admin setup can run. |
| `foundation-release-signing.md` | 2026-07-27 | **FRESH** | Operator procedure for publishing signed Claude/Codex foundation trees. |
| `ground-up-claude-codex-installation.md` | 2026-07-24 | **FRESH** | Phase-6 implementation/acceptance reference for a no-department-layer ENAC install. |
| `m5-owner-gated-batch.md` | 2026-07-17 | DRIFTED | "Security & credentials" owner-gated build-input doc; 2 Tauri + 13 MDM hits — likely largely historical/contextual (M5 predates the MDM-dropped decision in places) but not individually verified line-by-line. |
| `m9-owner-gated-split.md` | 2026-07-17 | **DRIFTED (self-aware)** | "M9 owner-gated split (Windows re-skin)"; explicit "BUILT-BUT-UNVERIFIED-ON-WINDOWS" honesty banner, but the whole doc is scoped to the Tauri/Rust Windows-re-skin plan documented in `windows-parity.md` — same staleness risk. |
| `README.md` | 2026-07-23 | DRIFTED | Deployment/Admin-guides index; carries its own "UNVALIDATED HYPOTHESIS" honesty banner (Founding Decision #9) but still has 8 Tauri + 8 MDM hits. |
| `standup-runbook.md` | 2026-07-21 | DRIFTED | Org-standup runbook for Admin mode; same "UNVALIDATED HYPOTHESIS" banner; 4 Tauri + 6 MDM hits. |
| `two-of-n-custody-runbook.md` | 2026-07-08 | FRESH-ish | Signing-custody runbook for release custodians; "UNVALIDATED HYPOTHESIS" banner; 2 Tauri hits, 0 MDM. |
| `windows-bringup.md` | 2026-07-17 | **DRIFTED (self-aware)** | Explicit top-of-file banner: "Pending reconciliation with the native-macOS direction (2026-07-08). Product direction is moving toward a native macOS app…" — correctly self-flags its own staleness; still 7 Tauri + 1 MDM hits in the body. |

### `docs/08-observability/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `observability.md` | 2026-07-09 | DRIFTED | Telemetry/observability spec ("Closing the Named Ecosystem Gap"); 4 MDM hits, not individually verified against CSE D4 conformance. |
| `operator-guide.md` | 2026-07-08 | DRIFTED | Fleet-dashboard operator guide; carries the "UNVALIDATED HYPOTHESIS" banner; 3 Tauri hits, 0 MDM. |

### `docs/10-reference/`

| File | Last mod | Verdict | One-line description |
|---|---|---|---|
| `copilot-solutioning-ecosystem.md` | 2026-07-10 | **FRESH** | Canonical CSE reference model that `docs/START-HERE.md` names as the corrected starting point for the whole repo. |
| `cse-alignment-decisions.md` | 2026-07-17 | **FRESH** | The authoritative decision record (D1–D10, incl. D4 "MDM dropped completely") that every other doc in the repo is supposed to conform to — this is the doc other docs' MDM mentions should be checked against. |
| `ecosystem-architecture.md` | 2026-07-22 | FRESH | "The Copilot Ecosystem — Final Architecture"; 0 Tauri/MDM hits. |
| `ecosystem-links.md` | 2026-07-11 | FRESH | Short pointer doc to where the broader ecosystem/tooling actually lives. |
| `ecosystem-use-cases.md` | 2026-07-10 | FRESH | Four-tier-model common use cases; 0 Tauri/MDM hits. |
| `four-tier-topology.md` | 2026-07-28 | FRESH | Four-tier extension model + GitHub account topology, recently touched; 0 Tauri/MDM hits. |
| `glossary.md` | 2026-07-10 | FRESH | Canonical term definitions; explicitly states "if a term is defined differently in an older doc, this page wins." |
| `publisher-admin-experience.md` | 2026-07-10 | FRESH | Defines the Publisher and Admin operational journeys before a fleet can run. |

---

## 5. CONTRADICTIONS between docs (numbered, highest value first)

1. **Shipping stack: Tauri v2 vs. native SwiftUI/AppKit.** `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/02-prd/prd.md`, `docs/01-architecture/architecture.md`, `docs/01-architecture/12-architecture-guiding-principles.md`, and `docs/01-architecture/windows-parity.md` all describe the app as Tauri v2/Rust/TypeScript/Vite (some as current, some as an active build target). `CLAUDE.md`, `docs/START-HERE.md`, and `docs/03-design/control-tower-native-experience-architecture.md`/`-interaction-spec.md`/`-visual-system.md` state the app is native macOS SwiftUI/AppKit (~19,600 lines of Swift, `native/*.swift`) and that "this supersedes the prior Tauri v2 / web-UI plan." The native-experience-architecture doc (2026-07-17) even explicitly notes it is overriding a then-stale `CLAUDE.md` line — but `architecture.md`, `prd.md`, `AGENTS.md`, and `windows-parity.md` were never brought into line, some as recently as 2026-07-27/07-30.

2. **Build status: "the build has not started" vs. shipped releases through v0.3.2.** `README.md`'s status line ("Private / pre-build… the architecture is complete and validated… the build has not started") directly contradicts `CHANGELOG.md` (dated releases 0.2.0 through 0.3.2, most recently 2026-08-01) and `docs/START-HERE.md` ("The app is built and shipped… Version 0.2.4 is the latest tagged release" — itself now stale by two further point releases, see #7 below).

3. **MDM: dropped completely (D4) vs. still described as a live mechanism.** `SOUL.md` v1.4 §9 Founding Decision #11 and `docs/10-reference/cse-alignment-decisions.md` D4 ratify "MDM is dropped completely… no `.mobileconfig`, no Jamf/Kandji/Intune flow." `SECURITY.md` still lists "MDM-managed config" as a sensitive surface; `CONTRIBUTING.md`'s feature-rejection table still cites "the forced/managed MDM domain" as the sole channel for security config; `docs/03-design/ui-ux/README.md` still instructs Product Creation Copilot to design "the MDM-profile generator" and points it at an architecture section titled "(Admin mode, MDM & IT enablement)."

4. **Windows plan: "committed re-skin over shared Tauri core" vs. no Tauri core to re-skin.** `docs/01-architecture/windows-parity.md` is a 129-line, deeply detailed Windows-parity tracker built entirely around Rust `#[cfg(windows)]` code, `src-tauri/src/platform/`, and six ADRs (ADR-M9-001…006) mapping macOS Tauri mechanisms to Windows equivalents. Its own top banner says this is "pending reconciliation" with the native-macOS pivot, but the reconciliation never happened — the doc's premise (a shared Tauri core exists to re-skin) is now false per contradiction #1, which would make the entire ADR-M9 series's Rust-side "Built, cfg-gated, macOS-green" claims moot for a Swift codebase, not merely deferred.

5. **Threat model still analyzes a Tauri webview attack surface that no longer exists.** `docs/05-security/threat-model.md`'s STATUS line calls the app "the Tauri binary" and its Elevation-of-Privilege row analyzes "unsanitized rendering of CLI-supplied strings in the **Tauri webview**," recommending mitigation via "the framework's default text-escaping path" and "the Tauri IPC command allowlist." A native SwiftUI/AppKit renderer has no webview and no IPC bridge to sandbox — this specific STRIDE finding is very likely obsolete as written (though the underlying risk class — rendering untrusted CLI-supplied strings — probably needs a native-equivalent finding, not zero finding).

6. **`docs/product-design/TODO-DESIGN-PACKAGE.md` names an obsolete "next step."** It records "SOUL.md — RATIFIED v1.3" (superseded by v1.4 two days later) and "Phase 6: Prototype — NOT STARTED (deferred — the build phase)," instructing a resuming session to "Choose ONE output format… Figma, Design Spec, Storybook, or Next.js." The actual build happened via a parallel, un-tracked-in-this-file path: three new native-app design docs (`control-tower-native-experience-architecture.md` etc., Stage 1–3) followed directly by hand-authored Swift — never a Figma/Storybook/Next.js Phase-6 artifact. Anyone picking up work from this file's stated "where I left off" pointer would be routed to a dead process.

7. **`docs/START-HERE.md` is itself already one and two point-releases behind `CHANGELOG.md`.** START-HERE.md states "Version 0.2.4 is the latest tagged release" and frames the "current job" as closing the Phase-7 transaction-fix gap discovered in that release. `CHANGELOG.md` shows three further releases since then (0.3.0, 0.3.1, 0.3.2, the last dated 2026-08-01, the day before this audit) with their own fixes to the onboard transaction model. START-HERE.md is the freshest "orientation" doc in the repo and still lagged behind by roughly 48 hours of shipped work — a useful data point on how fast this repo's ground truth moves relative to its docs.

---

## 6. Recommendations — keep vs. rewrite

**Keep as-is (accurate, load-bearing, well-maintained):** `CLAUDE.md`, `CHANGELOG.md`, `SOUL.md`, `docs/START-HERE.md` (minor version-number touch-up only), `docs/01-architecture/cli-contract.md`, `docs/01-architecture/schemas/README.md`, `docs/01-architecture/error-taxonomy.md`, `docs/01-architecture/inheritance-and-publish.md`, `docs/01-architecture/workspace-activation-contract.md`, `docs/01-architecture/admin-standup-contract.md`, `docs/00-overview/product-brief.md`, `docs/00-overview/soul.md` (pointer stub), `docs/03-design/control-tower-native-experience-architecture.md`/`-interaction-spec.md`/`-visual-system.md`/`-copy-deck.md`, `docs/05-security/credentials-and-boundary.md`/`security-and-trust.md`, `docs/10-reference/cse-alignment-decisions.md`/`copilot-solutioning-ecosystem.md`/`glossary.md`.

**Rewrite or hard-reconcile (actively misleading, not just aged):** `README.md` (stack + status line), `AGENTS.md` (stack line), `CONTRIBUTING.md` (Tauri dev-setup + MDM feature-rejection row), `SECURITY.md` (MDM reference + fill the security-contact TODO), `docs/01-architecture/architecture.md` (stack table — the doc's actual §2–§9 content may still be largely valid and just needs its stack claim and Windows-re-skin framing corrected), `docs/02-prd/prd.md` (Tauri task language throughout B1/D4/H4), `docs/01-architecture/12-architecture-guiding-principles.md` (System Context stack line — this one is actively read by agents before every architecture task), `docs/01-architecture/windows-parity.md` (needs either a full native-Swift-equivalent rewrite or explicit retirement into a historical-reference folder), `docs/05-security/threat-model.md` (retire or rewrite the Tauri-webview XSS finding into a native-equivalent finding), `docs/03-design/ui-ux/README.md` (retire — the Figma/Storybook/MDM-profile-generator ask no longer matches how design work or the build actually happened), `docs/product-design/TODO-DESIGN-PACKAGE.md` (either update Phase 6 to point at the native design docs that actually superseded it, or mark the whole package historical).

**Lower priority / re-verify against code before deciding:** `docs/04-validation/redteam-platform.md`/`redteam-use-cases.md`/`test-plan.md` (historically scoped under the Aviator/Tauri codename — findings may still be conceptually valid but were never re-run against the native rebuild), `docs/06-deployment/m5-owner-gated-batch.md`/`m9-owner-gated-split.md`/`windows-bringup.md`/`README.md`/`standup-runbook.md` (already self-flag as unvalidated hypotheses; the Tauri/MDM residue inside them is secondary to that larger honesty caveat), `docs/08-observability/observability.md`/`operator-guide.md`.
