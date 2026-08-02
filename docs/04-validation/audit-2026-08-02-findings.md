# Audit 2026-08-02 — findings from the documentation rebuild

| | |
|---|---|
| **Date** | 2026-08-02 |
| **Product version audited** | v0.4.0 (released 2026-08-02, build 19, embedded helper `cc 2.2.0`) |
| **Trigger** | A full documentation rebuild (commit `c70b66e`). The audit was a by-product: re-deriving the docs from code surfaced defects the docs had been concealing |
| **Method** | Parallel survey of the shipping Swift, release artifacts, CHANGELOG, ADRs and initiative evidence, cross-read against every documentation claim in the repository. Findings that made security or correctness claims were then re-verified by hand before being recorded |
| **Status** | **Findings recorded, not fixed.** The owner scoped that pass to documentation and explicitly forbade code changes ("the build is almost complete. Do NOT remove any code"). Everything below is an open item unless marked CLOSED or FIXED |

Ranked Critical → High → Medium → Low, in this repository's red-team format: **Area | Failure | Severity | Root cause | Fix**. Evidence appendices: [code ground truth](evidence-2026-08-02-code-ground-truth.md) · [pre-rebuild documentation audit](evidence-2026-08-02-doc-audit.md) · [rebuild brief and ratified answers](evidence-2026-08-02-retrofit-brief.md).

---

## Summary

| ID | Finding | Severity | Status |
|---|---|---|---|
| **C1** | The six invariants are stated but not enforced — every fitness test scans the retired Rust tree | Critical | Open |
| **H1** | Invariant #2's `launchd` crash-only watchdog is not implemented in the shipping app | High | Open |
| **H2** | Raw layer jargon ships on the most-read surface, and the ban is structurally unenforceable in the app | High | Open |
| **H3** | The primary persona has never been validated | High | Open |
| **H4** | The founding owner testimony survives in exactly one derived file | High | Open |
| **M1** | The ratified brand rule is violated — the logo is not bundled | Medium | Open |
| **M2** | Two divergent badge vocabularies; two badge states unreachable | Medium | Open |
| **M3** | No rollback instruction shipped with v0.4.0 | Medium | Open |
| **M4** | The documentation itself had drifted into active misinformation | Medium | **Fixed** (`c70b66e`) |
| **M5** | Admin mode has never been operated by anyone but its author | Medium | Open |
| **L1** | No accessibility verification of any kind exists | Low | Open |
| **L2** | Reduce Motion honored in one place; tray badge has no accessibility value | Low | Open |
| **L3** | `copilot.lock.json` is untracked and not ignored | Low | Open |
| **L4** | `src-tauri/Cargo.toml` frozen at 0.2.4 against a 0.4.0 product | Low | Informational |
| **CL1** | Apple Events / `NSAppleScript` command injection | — | **CLOSED — verified safe** |

---

## CRITICAL

### C1 — The invariants are stated but not enforced; every fitness test scans a tree that no longer ships

**Area:** Quality gate / architectural fitness functions

**Failure (concrete):** `CLAUDE.md` presents six invariants as the product's spine, and the repository carries **40 `fitness_*.rs` tests** that read as their enforcement — including `fitness_m5_no_wipe_logic.rs`, `fitness_m6_router_no_verdict_computation.rs`, and `fitness_m7_telemetry_content_free.rs`. Every one of them scans `src-tauri/src/**`. That is the **retired Rust implementation**. The shipping product is ~22,650 lines of Swift in `native/`, and not one line of it is visible to any fitness test. Compounding this, the release CI job that would run them is disabled behind `vars.RELEASE_CI_ENABLED`. The consequence is not that enforcement is weak — it is that **there is none**, while the repository's most-read file implies there is. Downstream, `docs/product-design/03-requirements/30-acceptance-criteria.md` records the true position: of 53 acceptance criteria, **10** have automated verification that gates a release, **18** have a harness that does not gate one, **1** rests on the single live run, and **24 rest on code review alone**.

**Severity:** Critical — not because an invariant is currently violated by the Swift, but because nothing would report it if one were, and the documentation actively encourages the reader to assume otherwise. A guarantee believed but unenforced is worse than a known gap: it suppresses the manual scrutiny that would have caught the regression.

**Root cause:** The fitness suite was written against the Tauri core and never migrated when the product was rebuilt in Swift. The tests kept passing — against dead code — so nothing signalled the loss. This is the same failure mode already recorded elsewhere in this ecosystem, where enforcement was documented but had never fired.

**Fix:** Port the fitness suite to scan `native/*.swift` and re-enable the release job. Until that happens, no document may claim the invariants are automatically enforced — the rebuilt docs now state them as architectural commitments upheld by review, with this gap named. When porting, treat the 24 review-only acceptance criteria as the priority list: they are exactly the claims with no mechanical backing today.

---

## HIGH

### H1 — Invariant #2's crash-only watchdog does not exist in the shipping app

**Area:** Process model / persistence

**Failure:** `CLAUDE.md` invariant #2 specifies `launchd` as a **crash-only watchdog** (`KeepAlive={SuccessfulExit:false}`, never `true`) — a deliberate, hard-won design position, arrived at after an earlier red-team review established that `KeepAlive=true` produces crash-loop storms and prevents a user quitting their own app. That watchdog exists **only in the retired Rust tree**. The shipping Swift app implements no watchdog at all. The invariant therefore describes a design intent, not a property of the product.

**Severity:** High — the practical exposure is modest (a crashed tray simply stays down until relaunched, which is failure-safe rather than failure-dangerous), but the invariant is stated as fact in the file that governs all development, and a future contributor will reasonably build on the assumption that it holds.

**Root cause:** Same migration gap as C1 — a behavior that lived in the Rust core was not carried into the Swift rewrite, and no test could notice because the tests scan the Rust core.

**Fix:** Either implement the crash-only watchdog in the shipping app, or amend invariant #2 to state the watchdog as a deferred design position rather than a current property. The rebuilt documentation takes the second course as an interim measure and names this as an open item; it should not stay interim indefinitely.

### H2 — Raw internal vocabulary ships on the most-read surface, and the ban cannot be enforced where the leak occurs

**Area:** Copy / accessibility / the democratization essence

**Failure:** `native/control-tower-tray.swift:1375` renders `foundation: pass · organization: warn · department: pass · personal: pass` beneath every copilot name in the tray's `YOUR COPILOTS` region — raw layer identifiers plus the CLI's raw severity enum, on the surface a user sees most often. The ratified plain-language labels (`Core setup` / `Your organization` / `Your department` / `This Mac`) exist **25 lines earlier in the same file** and are bypassed. It recurs on the wizard's "Your copilots are ready" screen (`native/wizard.swift:5874`), and VoiceOver speaks it as *"Claude Copilot, warn"* (`native/control-tower-tray.swift:1387`). Seventeen further leaks are catalogued with file and line in `docs/product-design/04-experience-design/70-copy-voice.md`.

This directly violates the product's own essence. The ratified position is that a non-technical person is the specification, and `SOUL.md` v2.0 names the failure mode **The Machine Talking To Itself** and marks it as a live, currently-shipping violation.

**Severity:** High. The product's entire claim is that a person who does not know what a layer is can run this unaided; a string requiring exactly that knowledge, on the primary surface, contradicts the claim at the point of contact.

**Root cause — the important half:** this is not merely a missed call site. **The ban is structurally unenforceable inside the app.** Under invariant #1 the app parses and renders CLI output without computing, so CLI-authored `detail` prose passes straight through to the user untouched. No amount of discipline in the Swift can guarantee plain language when the words originate upstream. Fixing the two known call sites would close the visible symptom while leaving the mechanism intact.

**Fix:** Two parts, and the second matters more. (a) Route the tray and wizard call sites through the existing plain-label mapping. (b) Move the plain-language requirement into the **`cc` contract itself** — every user-facing `detail` string the CLI emits must satisfy it, verified CLI-side, because that is the only layer with the authority to guarantee it. Treat the app-side fix as symptom relief and the contract change as the actual remedy.

### H3 — The primary persona has never been validated

**Area:** Product evidence / research

**Failure:** Bob — the change-averse non-technical adopter — is the primary persona, and every design decision in the package is justified against him. He is grounded in real observation of real people. But **no non-technical person outside the owner is known to have completed setup unaided.** The product has run 16/16 live apply on one organization, operated throughout by its author. The one claim the product exists to make — that someone who cannot check it will nonetheless be able to run it — is the one claim with no evidence behind it.

**Severity:** High. This is the single highest-value unmeasured fact about the product, and it gates the honest status claim.

**Root cause:** Dogfooding on a single organization whose only operator is the product's author. The design has been validated for correctness, never for its central accessibility premise.

**Fix:** The **V-5 cold-laptop proof** already on the roadmap is the right instrument — a two-machine onboarding run against an empty keychain — but it must be run by someone who is *not* the owner for it to test the actual claim. Until it is, `docs/product-design/00-overview/20-success-metrics.md` correctly carries this as a marked gap rather than an assumed success.

### H4 — The founding owner testimony survives in exactly one derived file

**Area:** Evidence provenance / continuity

**Failure:** `SOUL.md` v1.4 credits `scratchpad/interview-ground-truth.md` as the primary-evidence owner interview that reframed the product's essence to democratization — the single most consequential decision in the product's history. **That file no longer exists.** It was gitignored, never committed, and is absent from every ref. The only surviving record is eight verbatim quotes from 2026-07-06 preserved inside `docs/product-design/01-research/10-interviews/01-interview-self.md`. The rationale for the product's essence now rests on one derived document with no primary source behind it.

**Severity:** High for continuity. Nothing is broken today, but the reasoning cannot be re-examined, and a future disagreement about what the essence means has no authority to appeal to.

**Root cause:** Primary evidence was captured into `scratchpad/`, which is gitignored by design.

**Fix:** Never capture primary owner testimony in `scratchpad/`. The eight surviving quotes are now explicitly marked in the interview document as the sole record, with the loss flagged in place. If any recording, transcript or notes of that 2026-07-06 conversation still exist anywhere, committing them is the highest-value archival act available.

---

## MEDIUM

### M1 — The ratified brand rule is violated because the logo is not bundled

**Area:** Visual identity / packaging

**Failure:** The ratified rule is that the Control Tower icon is the logo and the aviator glyph is the menu-bar mark. `control-tower-logo.svg` is **not bundled into the app**, so the wizard hero falls back to the SF Symbol `building.2`. The first screen a new adopter sees therefore does not carry the product's identity.

**Severity:** Medium — cosmetic in effect, but it lands on the first-run surface, and it silently contradicts a decision that was explicitly ratified.

**Root cause:** An asset-pipeline omission; the packaging script compiles Swift and signs, and nothing verifies that referenced assets resolve.

**Fix:** Bundle the asset, and add a build-time check that every referenced named image resolves — a fallback that renders successfully is precisely the kind of failure no test notices.

### M2 — Two divergent badge vocabularies, and two states that cannot be reached

**Area:** Status vocabulary / information architecture

**Failure:** The tray uses a closed **12-badge** vocabulary. Settings maintains a **separate 5-state** vocabulary for the same underlying truth. Additionally, the `update` and `spinner` badges are defined but **unreachable** — `render-state` collapses both onto `ring`.

**Severity:** Medium. Divergent vocabularies for one truth are how a status surface starts lying by omission; dead vocabulary is a smaller matter but signals the same drift.

**Root cause:** Settings was built after the tray vocabulary was settled and did not adopt it; the collapsed badges are leftovers from a state model that changed underneath them.

**Fix:** Collapse to one vocabulary with one owner. Either reach the two dead states or remove them — a defined-but-unreachable state is a claim the product cannot make.

### M3 — No rollback instruction shipped with v0.4.0

**Area:** Release practice

**Failure:** The v0.4.0 changelog entry carries no Rollback section. A user or operator who needs to return to v0.3.2 has no documented path, despite seven signed releases being retained under `release/` precisely so that is possible.

**Severity:** Medium — the capability exists; only the instruction is missing.

**Root cause:** Rollback guidance is not part of the release template.

**Fix:** Add a Rollback section to the release template so it cannot be omitted, and backfill v0.4.0.

### M4 — The documentation had drifted into active misinformation — **FIXED**

**Area:** Documentation integrity

**Failure:** Of roughly 80 documents audited, **~10 were CONTRADICTED and ~30 DRIFTED**. `README.md` stated the build had not started, against seven signed releases. Six documents named Tauri v2/Rust as the shipping stack. Three described MDM (Jamf/Kandji/Intune) as live, nearly a month after it was formally dropped. `windows-parity.md` carried a full ADR series written against a core that no longer exists. `threat-model.md` analysed a Tauri webview XSS finding that a native renderer cannot have. `TODO-DESIGN-PACKAGE.md` pointed any resumer at a Figma/Storybook phase that never happened.

**Severity:** Medium as a defect, but it is the finding that generated every other finding in this report — the drift is what let C1 and H1 sit unnoticed.

**Root cause:** The documents were written once, at a point in time, with no mechanism tying them to the code they described. The product then changed stack, dropped a deployment mechanism, and shipped eight version lines. Nothing forced reconciliation.

**Fix — applied in `c70b66e`:** all 15 facilitated documents plus `SOUL.md` re-derived from evidence; ten contradicted documents outside the package repaired; `windows-parity.md` retained in full with a superseded banner. The durable fix is not this rebuild but the practice it implies: **documentation that asserts a technology, a version, or an enforcement mechanism should be re-verified whenever that thing changes**, and a claim with no evidence behind it should be marked, not asserted.

### M5 — Admin mode has never been operated by anyone but its author

**Area:** Product evidence / the Earl persona

**Failure:** The 16-surface Admin app, and the organization-standup flow it drives via `admin_bootstrap.sh`, has been **run once, by the author**. No third-party IT operator has ever touched it. Earl — the enabling admin persona — is a model-in-head, and the design package now says so explicitly.

**Severity:** Medium. It is a real untested bet, but it gates organizational adoption rather than the primary individual journey (H3 is the higher-value gap).

**Root cause:** Single-organization dogfooding.

**Fix:** Pair the V-5 proof with an Admin run performed by someone other than the author, and record what they could not do unaided.

---

## LOW

### L1 — No accessibility verification of any kind exists

**Area:** Accessibility

**Failure:** No contrast audit, no light/dark Dynamic Type proof, no keyboard pass, and no pinned tab order exist anywhere for any surface.

**Severity:** Low only in the sense that no specific violation is proven — which is the point: nothing has been checked, so nothing is known.

**Root cause:** Never scheduled.

**Fix:** A single pass across the tray popover, the nine wizard stages and Settings would establish a baseline. Record the result even if it is clean, so the absence of a finding stops reading as an absence of checking.

### L2 — Reduce Motion honored in one place; the tray badge has no accessibility value

**Area:** Accessibility

**Failure:** Reduce Motion is honored in exactly one call site out of four motion sites. The tray item carries no `accessibilityValue` naming its badge, so the single most information-dense element in the product is not exposed to assistive technology by name — compounding H2, where what *is* exposed is raw jargon.

**Severity:** Low individually; taken with H2 and L1, the accessibility story is the weakest area of an otherwise carefully-built product.

**Fix:** Honor Reduce Motion at all four sites; give the tray item an accessibility value drawn from the same plain-label mapping H2 calls for.

### L3 — `copilot.lock.json` is untracked and not ignored

**Area:** Repository hygiene

**Failure:** A `copilot`/`cc` run during the audit session produced `copilot.lock.json` at the repository root. It is a machine-local state artifact, it is untracked, and it is **not** covered by `.gitignore` — so it will surface in every future `git status` and is one careless `git add -A` away from being committed.

**Severity:** Low.

**Fix:** Add it to `.gitignore`. Not done here because `.gitignore` is not documentation and this pass was scoped to documentation.

### L4 — `src-tauri/Cargo.toml` frozen at 0.2.4 against a 0.4.0 product — *informational*

**Area:** Retired code

**Failure:** Everything in the repository moved to 0.4.0; the Rust manifest sits at **0.2.4**. This is not a defect — it is the cleanest available *proof* that the Tauri tree is retired, and the rebuilt scope document cites it as such.

**Severity:** Informational. Recorded so a future reader does not mistake the version skew for neglect and "fix" it, and so the retirement has a citable fact behind it.

**Note:** The tree stays on disk by explicit owner instruction. It still supplies the app icon and bundle identifier, and it still holds the fitness suite from C1 — so it cannot be removed before that suite is ported.

---

## CLOSED

### CL1 — Apple Events / `NSAppleScript` command injection — **verified safe**

**Area:** Security / Terminal automation

**Claim as raised:** The retired Tauri-era threat model carried an unsanitized-webview-rendering finding. That mechanism cannot exist in a native SwiftUI renderer, which raised the right question: *what replaced that surface?* `ProjectIntegrationLauncher` (`native/control-tower-tray.swift:439`) drives Terminal via Apple Events to launch an assistant in a detected project folder, and project names and paths originate from git-repo content across tiers. If any of those reached the Apple Events call unescaped, it would be same-user code execution.

**Verdict: CLOSED — audited by hand 2026-08-02, escaping is present and correct at every site.**

- `shellQuote` (`:584`) wraps values in single quotes using the canonical POSIX `'"'"'` escape, and is applied to the executable path, the project path and the prompt-file path (`:534-536`).
- `appleScriptLiteral` (`:588`) escapes backslash **first**, then double-quote, then newline — the correct order, with no residual escape-sequence bypass — and is the only path by which the command string reaches `NSAppleScript` (`:563-570`, `:509-511`).
- Decisively, the most attacker-influenced value — the prompt body — **never enters the command string at all.** It is written to a temp file with `0o600` permissions and read back through a correctly double-quoted command substitution (`:491-508`, `:540-542`).

This is a deliberately hardened path, not an incidental one.

**Residual, low:** `resolveExecutable` (`:597`) shells `/bin/zsh` to resolve the assistant command name and so inherits the user's `PATH`. An attacker who can already write that user's `PATH` has better options than this.

**Recorded rather than deleted** because the reasoning — *the old finding is moot, but what surface replaced it?* — is the question worth re-asking whenever the automation path gains a call site or a new interpolated value.

---

## What this audit says about the product

Two observations worth more than any individual finding.

**The defects cluster in verification, not in construction.** C1, H1, H3, M5, L1 and L2 are all the same shape: the thing was designed carefully, built carefully, and then never checked — or checked by an instrument pointed at the wrong target. The code the audit read is notably disciplined; CL1 in particular found a security path hardened well beyond what the threat model claimed for it. What is missing is the layer that would notice if that discipline ever lapsed.

**The product's own standard is the right one to judge it by.** `SOUL.md` v2.0 ratifies *say only what you can prove* as the highest principle, above even parse-never-compute, on the strength of a 2026-07-31 incident where the app faithfully rendered a false claim. By that standard, C1 and M4 are the same defect wearing different clothes: a claim asserted without evidence to back it. The product held itself to that bar in its user-facing copy long before its documentation met it. This audit is the documentation catching up.
