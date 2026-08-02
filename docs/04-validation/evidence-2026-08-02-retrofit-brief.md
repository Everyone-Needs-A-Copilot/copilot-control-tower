> **Evidence appendix — captured 2026-08-02.** The working brief every agent in the documentation rebuild wrote against: the hard constraints, the owner's ratified answers (A-1…A-5), the ground-truth facts, and the named gaps. Preserved because it is the record of *what the rebuild was instructed to do* — useful when checking whether a rebuilt document actually honored its constraints. Readable summary: [`audit-2026-08-02-findings.md`](audit-2026-08-02-findings.md).

---

# Retrofit Brief — Copilot Control Tower documentation rebuild

**Date:** 2026-08-02. **Target repo:** `/Volumes/Dev/Sites/COPILOT/copilot-control-tower`. **Process:** `product-creation-copilot` soul-retrofit, full-rebuild-from-evidence calibration.

This brief is the constitution for every agent writing documentation in this rebuild. Read it fully before writing a word. Where it conflicts with an existing document in the repo, this brief wins — the existing documents are what we are replacing.

---

## Hard constraints (non-negotiable)

1. **Documentation only. Do NOT modify, delete, move, or refactor ANY source code.** The build is almost complete and the owner has explicitly forbidden code changes. No edits to `native/**`, `src-tauri/**`, `src/**`, `scripts/**`, `packaging/**`, `tools/**`, `package.json`, or any `.swift` / `.rs` / `.ts` / `.sh` file. You write `.md` files and nothing else.
2. **Do not delete or move any file.** If a document is superseded, add a clearly-marked banner at its top saying so. Never `rm`, never `mv`.
3. **No time estimates.** Never write hours, days, weeks, months, sprints, quarters, or completion dates. Use phases, priority (P0–P4), complexity, and dependencies.
4. **No hard-wrapped prose.** One paragraph is one line, however long. Real newlines only for paragraph breaks, headings, list items, table rows, and code blocks. This applies to every file you write.
5. **Do not invent.** Every factual claim must trace to evidence in the repo or to the ratified owner answers below. If you cannot source it, mark it `<!-- TODO: [what needs confirming] -->` and move on. An honest gap beats a confident fabrication — the entire reason for this rebuild is that the old docs claimed things that were not true.

---

## Evidence base (read these first)

| Source | Path | What it gives you |
|---|---|---|
| Code ground truth | `scratchpad/GROUND-TRUTH-CODE.md` (this scratchpad dir) | What the product actually is and does today, with file:line citations |
| Documentation audit | `scratchpad/DOC-AUDIT.md` (this scratchpad dir) | What every existing doc claims + staleness verdict + the contradiction list |
| Invariants | `<repo>/CLAUDE.md` | The six invariants. FRESH — trust it, except that its enforcement claim is aspirational (see gap G-1) |
| Shipped history | `<repo>/CHANGELOG.md` | FRESH — the real release history through v0.3.2 |
| CLI contract | `<repo>/docs/01-architecture/cli-contract.md` + `docs/01-architecture/schemas/` | FRESH — the verb/schema seam |
| Inheritance model | `<repo>/docs/01-architecture/inheritance-and-publish.md` | FRESH |
| Credentials boundary | `<repo>/docs/05-security/credentials-and-boundary.md` | FRESH |
| CSE alignment | `<repo>/docs/10-reference/cse-alignment-decisions.md` | FRESH — decisions D1–D10, including D4 (MDM dropped) and D10 (a project is self-contained, not a layer) |
| Native design triad | `<repo>/docs/03-design/ui-ux/control-tower-native-experience-architecture.md`, `…-interaction-spec.md`, `…-visual-system.md` | FRESH — the real native design |
| ADRs | `<repo>/docs/40-initiatives/02-enac-self-onboarding/decisions/ADR-00{1..8}*.md` | All Accepted. ADR-006/007/008 are load-bearing |
| Prior soul | `<repo>/SOUL.md` (RATIFIED v1.4) | Mine it for reasoning and decision history, but the rebuild supersedes it. Its §9 Founding Decisions are largely still valid and should carry forward with dates |

**Do NOT treat these as evidence — they are CONTRADICTED and are being replaced:** `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/01-architecture/architecture.md`, `docs/02-prd/prd.md`, `docs/01-architecture/12-architecture-guiding-principles.md`, `docs/01-architecture/windows-parity.md`, `docs/03-design/ui-ux/README.md`, `docs/05-security/threat-model.md`, `docs/product-design/**` (all 15 documents + tracker).

---

## Ratified owner answers (2026-08-02)

These are the gap-closing decisions from the owner (Pablo). They are settled. Do not re-litigate them, and do not soften them.

### A-1 — Audience

Three readers, in this order of weight:

1. **The owner's future self / session continuity.** Any future session must be able to pick this product up without re-deriving it. Optimize for accuracy, decisions-of-record, and honest current state.
2. **Buyers and non-technical evaluators.** People deciding whether to adopt it. They need the job it does and the journey, not the internals.
3. **Teams and organizations looking for new ways to transform their organization.** This is a *positioning* audience — the docs should make it legible what adopting this does to an organization, not just what the binary does on a laptop.

Notably NOT an audience: open-source contributors wanting to submit patches, and developers receiving a handoff. Do not optimize for either. Contribution mechanics stay minimal.

### A-2 — Essence: still DEMOCRATIZATION

The essence is unchanged from SOUL v1.4: **a technical person's superpowers in a non-technical person's hands.** Organizations are the *buyer*; the individual is where the value lands. The Feature Filter tests against the mechanism (democratization), not against the outcome (organizational transformation). Do not rewrite §2 of the soul around org transformation — the owner explicitly rejected that framing.

### A-3 — Status: DOGFOODING, live on one org

The honest public claim. Running in production on ENAC. Phase 7 reached **16/16 live apply**. Not yet offered to outside organizations. Documents must say this plainly and name what remains: the **V-5 cold-laptop proof** and the **publicize** step. Never claim "the build has not started" (the current README's claim — it is false, seven signed releases exist) and never claim general availability.

### A-4 — Killed and out-of-scope technology

| Technology | Status | How to document it |
|---|---|---|
| **Tauri v2 / Rust core** | Dead as the shipping stack. **The code tree stays on disk — do not remove it, do not propose removing it in this pass.** | Every doc stops describing Tauri/Rust as the stack. The shipping app is native SwiftUI/AppKit. Where a doc must mention `src-tauri/`, describe it as the retired reference implementation that remains in-tree. |
| **Windows** | **Formally out of scope.** macOS-only is the documented position. | Add a superseded banner at the top of `docs/01-architecture/windows-parity.md` stating it was written against the retired Rust core and Windows is out of scope. Leave the file in place; do not move or delete it. |
| **MDM (Jamf/Kandji/Intune)** | **Dropped completely as a mechanism** — already ratified in SOUL v1.4 D4 and `cse-alignment-decisions.md` D4. | Scrub live-MDM claims from `SECURITY.md`, `CONTRIBUTING.md`, `docs/03-design/ui-ux/README.md`. Security posture is **compiled-in trust roots plus signed, inherited org/foundation config** — nothing else. |

### A-5 — Invariant enforcement: document honestly as a named gap

See gap G-1. No document may claim the invariants are automatically enforced. State which are upheld by architecture and review, and record the enforcement port as an open item. The owner chose honesty over both fixing it now and quietly reframing it away.

---

## ⚠️ VERSION CORRECTION — the product is v0.4.0, not v0.3.2

**This supersedes every "v0.3.2" reference below and anywhere else in this brief.** Three commits landed in this repository at 09:28, 09:43 and 09:48 on 2026-08-02 — after the code survey was taken. Verified against git.

- **Current version is 0.4.0** (build 19), commits `86b84c5` (app), `453d15f` (release), `2d95ba8` (macOS release artifact). It is a MINOR bump for a genuine new feature, not a patch.
- **The connections bridge SHIPPED.** The ground-truth report's note about "+541 uncommitted lines" is now **stale** — that work is committed and released. Do not describe the connections bridge as in-flight or uncommitted.
- **The wizard's step 6 "Your connections" is new in 0.4.0** and renders the organization's full **20-service roster** with real `secret_state` (`ready` | `needs-connect` | `no-store`), in Settings as well as the wizard. It closes what was an empty-state gap. Control Tower filters purely on the CLI-computed `secret_state` — it never inspects a secret value and never computes connection state itself. This is invariant #1 (parse, never compute) working exactly as designed, and it is a good concrete example to cite.
- **The embedded helper is now `cc 2.2.0`** (0.3.2 shipped cc 2.1.2). `cc connections --json` is CLI-side end to end: it shells `copilot --json layers` against cli-copilot foundation ≥ v0.3.2 and presence-checks each service's hinted secret names against the organization's shared Infisical store. 0.4.0 is also the first app release carrying cc 2.1.3–2.1.5 (`resolve --explain` subpath join; never-destroy now holds a committed customization to a framework-owned project file rather than overwriting it; `fold` falls back to the newest verified layer when the nominal winner is blocked-unverified).
- **`controltower.compat.json` is unchanged** — cc 2.2.0 falls inside the existing `2.0.0 – <3.0.0` window. Schema range stays `1.0 – 2.0`.
- A phantom secret-store provisioner that could report a store as configured when it was not is **fixed** in cc 2.2.0.

**Everything else in this brief still holds**, including all ratified owner answers and gaps G-1/G-2/G-3. Where a section below says v0.3.2, read v0.4.0. When you write a status line, use **v0.4.0**.

---

## Ground truth: what this product IS today

Use these facts. They come from the code survey; cite the source report for detail.

- **~22,650 lines of Swift**, compiled by `swiftc` into three executables: `Copilot Control Tower.app` (7 native files), `Copilot Control Tower Admin.app` (same 7 plus `admin.swift` / `admin-support.swift`, built with `-D CT_ADMIN_BUILD`), and the owner-only `Publisher Setup.app`.
- **Current version 0.3.2** (2026-08-01, commit `e0bf0c3`) — notarized arm64 DMG embedding pinned, notarized **cc 2.1.2**. 15 tags exist; 7 signed releases retained under `release/`.
- **Tauri is dead code**: `scripts/package-user-release.sh` never invokes cargo or npm, and `src-tauri/Cargo.toml` is frozen at `0.2.4` while everything else is `0.3.2`.
- **The real user surface**: a menu-bar tray with a **12-badge vocabulary** on a **300-second poll** (Sync now / What changed / Settings / Quit); a **9-stage wizard** (welcome → connect GitHub → detect → what you're getting → departments → Your connections → Your projects → Set up → Verify); a **Settings** window rendering 4 components × 4 tiers; and a **16-surface Admin** app driven by `admin_bootstrap.sh` (bash, with vendored `gh` and `jq`).
- **Verbs actually consumed**: `doctor`, `auth status/login/grant`, `layers [join]`, `freshness [--all-projects]`, `update [--fanout|--project]`, `onboard` (personal + org), `workspace` (9 subverbs), `connections`. The app **never** calls `resolve`, `deprovision`, `publish`, or `repair` — the latter two are formally deferred per ADR-008.
- **Per-verb schema gate**: `onboard` requires major **2**; all other verbs require major **1**. Compat pin is cc `2.0.0 – <3.0.0`, schema `1.0 – 2.0` (`controltower.compat.json`).
- **ADR-001 … ADR-008 are all Accepted.** ADR-006 (preflighted saga), ADR-007 (breaking schema v2), and ADR-008 (repair + publish deferred) are the load-bearing three.
- **Initiative status**: `02-enac-self-onboarding` reached **16/16 live apply** in Phase 7; remaining are the V-5 cold-laptop proof and the publicize step. `03-schema-mismatch` is **complete** — it documents the incident where a manifest field rename took down every Claude Code prompt.
- **MDM, deprovision, telemetry, self-update, the launchd watchdog, and all Windows code exist only in the retired Rust tree.** There are zero references to any of them in `native/`.

### Uncommitted work in the tree

**+541 lines** of `cc connections` bridge across 5 native files are uncommitted — the documentation for that verb shipped (commit `fc90a5e`) but the app code did not. Note this as current in-flight state where relevant; do not commit it, and do not modify it.

---

## Known gaps to document honestly

These are real defects found during the survey. They must appear in the rebuilt documentation as named, open items — not hidden, not softened, and not silently fixed.

### G-1 — The invariants are stated but not enforced

All **40 `fitness_*.rs` tests scan `src-tauri/src/**`** — the retired Rust tree. They cannot see a single line of the shipping Swift. The CI job that runs them is disabled behind `vars.RELEASE_CI_ENABLED`. Consequence: the six invariants in `CLAUDE.md` are architectural commitments upheld by review, **not** automatically-enforced properties of the shipping app. Porting the fitness suite to scan `native/*.swift` and re-enabling the job is an open item. Per A-5, document it; do not fix it in this pass.

### G-2 — Invariant #2's watchdog is not implemented

`CLAUDE.md` invariant #2 describes `launchd` as a crash-only watchdog (`KeepAlive={SuccessfulExit:false}`). That watchdog exists only in the retired Rust tree; the shipping Swift app does not implement it. Document the invariant as the stated design position and the absence as an open item.

### G-3 — Phase 6 of the design package never happened as written

`TODO-DESIGN-PACKAGE.md` points a resumer at a Figma/Storybook/Next.js prototype phase. None of that occurred — the app was hand-built in native Swift on a separate design track that produced the native design triad in `docs/03-design/ui-ux/`. The rebuilt tracker must reflect what actually happened: Phase 6's output is the shipping native app plus that triad.

---

## Output conventions

- **SOUL.md** is written to the **repo root**, not inside `docs/`. It is a cross-phase decision instrument. Rebuild it against `product-creation-copilot/templates/SOUL.md` (the 10-section structure) and the Define-Done bar in `product-creation-copilot/skills/REF-soul-file.md`. Target status: **RATIFIED v2.0**, dated 2026-08-02, with a changelog row in §10 explaining that it was rebuilt from evidence after the docs drifted from a shipping product.
- **Design package documents** go to `docs/product-design/<phase-folder>/<filename>.md`, overwriting the existing stale file at that exact path. Keep the filenames exactly as they are.
- **Preserve the facilitation guides.** Each template document carries an HTML comment block marked `FACILITATION GUIDE`. Carry it forward into the rebuilt document — it is the package's core value and must survive the rebuild.
- Every rebuilt document gets a status line near the top: the date (2026-08-02), that it was rebuilt from evidence, and the product version it describes (v0.3.2).
- Write for A-1's readers: precise enough for the owner's future self, legible to a non-technical evaluator. Prefer the product's own vocabulary — the words the code and the wizard actually use — over invented terminology.
