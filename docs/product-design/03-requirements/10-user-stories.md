# User Stories

> **Provenance.** Grounded translation, not fresh invention. Stories are derived from the ranked
> Jobs-to-Be-Done (`02-service-design/30-jtbd.md`), the journey maps + struggling moments
> (`20-journey-maps.md`), the moments that matter (`40-moments-that-matter.md`), the Soul's Feature
> Filter (`SOUL.md` — anything ruled OUT does **not** appear here), and the engineering PRD's per-task
> acceptance prose (`02-prd/prd.md`, `01-architecture/architecture.md`, `cli-contract.md`). Each story
> carries inline, independently verifiable acceptance criteria; the rigorous Given/When/Then form plus
> performance / quality / data-quality thresholds live in [`30-acceptance-criteria.md`](30-acceptance-criteria.md).
> Genuine unknowns are marked `<!-- TODO -->`.
>
> **Priority basis (locked, Pablo 2026-07-06 — Bob-first, `SOUL.md` §9):** Operator (Bob) stories are
> the **P0 spine**. Admin-mode stories are **P0 only where they enable a working Bob**, else P1.
> Ecosystem-owner (Pablo) stories are mostly P1/P2 *except* the integrity/security invariants the
> whole product rests on, which are P0. "Bob is not a reliable actor" is load-bearing throughout.

---

## Personas (carried from Phases 1–2)

| Code | Persona | Mode | Role in the priority model |
|------|---------|------|-----------------------------|
| **B** | **Bob** — non-technical employee | Operator | **Primary.** The P0 spine. No terminal, denies OS prompts, ignores single nudges, may run Focus/DND. |
| **A** | **Raj** — IT / Admin operator | Admin | The **enabler.** P0 where it makes a working Bob possible, else P1. |
| **O** | **Pablo** — ecosystem owner / ENAC maintainer | Trust basis | Mostly P1/P2; P0 for the parse-never-compute + security invariants. |
| **D** | **Jane / Sam** — developer-contributor | CLI (secondary) | Do-no-harm only. Success = they never notice Control Tower. |

---

## Bob — Non-Technical Employee (Primary) Stories

### Onboarding — The Silent First Light (MTM-1, job B1)

**US-B01 (P0):** As Bob on a managed Mac, when IT has pushed the app + a complete `.mobileconfig`, I want the partner to provision **silently** (I watch a progress bar and am asked nothing), so that I get a working, team-scoped Copilot partner without ever seeing a terminal.

**Acceptance Criteria:**
- Zero questions are presented when the managed profile is complete-for-silent.
- The wizard schema-validates the managed profile **before** entering silent mode.
- On success the icon reaches **Healthy** and a working host (Claude and/or Codex) is present.
- No terminal window ever appears. (perf: p90 push→terminal-state ≤ 10 min — PROVISIONAL)

---

**US-B02 (P0):** As Bob on an **unmanaged** Mac, when I double-click the app, I want to be asked **at most three** things (host only if ambiguous, one sign-in approve, company/team), so that I can set up without technical knowledge.

**Acceptance Criteria:**
- Unmanaged setup asks ≤ 3 questions; OS/arch, prereqs, repo URLs, product set, git identity are all derived.
- The sign-in uses a GUI device flow (8-char code + browser), never a terminal.
- Company/team is a confirmed pick-list, never free-text YAML.

---

**US-B03 (P0):** As Bob, when IT's managed profile is missing or has a malformed required key, I want the app to **fail closed into a distinct *IT-config-incomplete* state** (wrench badge) and escalate to IT, so that I am never silently wired to an empty/wrong department and shown Healthy.

**Acceptance Criteria:**
- A missing/malformed required key → **IT-config-incomplete**, never Healthy, never a hang. (fixes A-C1/B-H4)
- *Absent* keys retry over a settling window (absorbs partial MDM apply); *present-but-invalid* fails immediately with `IT config error: <key>`.
- A content-free safety signal (`stalled-onboarding` / config-incomplete) reaches the IT `AdminContact` channel.

---

**US-B04 (P0):** As Bob on home wifi with a new laptop, when the first run completes foundation-only offline, I want a distinct **Waiting-for-network** state (clock badge), so that I am never shown a false-Healthy over a half-provisioned machine.

**Acceptance Criteria:**
- Offline first-run enters **Waiting-for-network**, never Healthy and never a scary error. (fixes A-H7)
- The supervisor completes company clones automatically on reconnect, with no re-wizard.
- "Seed not yet published" is distinguished from "solo user" via the managed `EcosystemSeedURL`. (fixes A-H12)

---

**US-B05 (P0):** As Bob, when I quit the app partway through setup, I want the setup to **resume headlessly** on next login, so that an interrupted install finishes itself without restarting from zero.

**Acceptance Criteria:**
- The login-item + crash-watchdog are installed at the **first** wizard phase, not the last. (fixes A-H6)
- A checkpoint is persisted at each phase; a mid-wizard quit resumes from the last checkpoint.
- No user action is required to resume.

---

**US-B06 (P1):** As Bob, when setup completes, I want a short **teach step** (plain-language cheat sheet + "add your first skill" + a backup offer), so that I know how to use my new partner.

**Acceptance Criteria:**
- The teach panel shows on first successful completion and can be re-opened from the menu.
- The wizard window foregrounds during setup (Accessory→Regular) and returns to Accessory after. (fixes B-L1)

---

### Honest status — The Icon That Cannot Lie (MTM-2, job B3)

**US-B07 (P0):** As Bob, when I glance at the menu bar, I want the icon to be an **honest projection of `doctor --json`** that can never fabricate Healthy, so that I can trust in half a second that "it's OK, and I don't have to do anything."

**Acceptance Criteria:**
- Status is **parsed from the CLI, never computed by the app** (invariant #1). (fixes O3)
- The app has **no code path** that can render Healthy without a fresh CLI `status: healthy`.
- Missing security-relevant `--json` fields **fail closed to fail**, never to safe/green. (fixes B-H6)
- **False-Healthy rate = 0** (hard invariant, not a threshold — any occurrence is a Critical regression).

---

**US-B08 (P0):** As Bob with two hosts, when only one host is broken, I want the status line to **name the failing host** in plain language ("Codex needs sign-in; Claude is fine"), so that I learn a fact, not a blur.

**Acceptance Criteria:**
- The dropdown top line names the specific failing host, never a blended "needs attention." (fixes A-M14)
- Status is worst-wins across hosts but attribution is per-host.
- Updates are per-host transactional: Claude success + Codex failure leaves a consistent lock per host.

---

**US-B09 (P0):** As Bob, when the machine is in a non-Healthy but honest state, I want each state to have a **distinct, meaningful badge** (wrench = IT-config-incomplete, clock = Waiting-for-network, key = Signed-out), so that state is never conveyed by color alone.

**Acceptance Criteria:**
- Each honest holding state renders a distinct shape/badge + a plain-language sentence, not color alone.
- State precedence follows `IT-config-incomplete > Signed-out > Needs-attention > Offline > Syncing > Update-available > Healthy`.
- State transitions occur **only** from fresh CLI JSON.

---

### Steady-state self-heal — it stays working on its own (job B2)

**US-B10 (P0):** As Bob, when my machine drifts, falls behind, or loses sync while I'm just working, I want it to **self-heal reversible drift automatically** without interrupting me, so that I can trust it's current without babysitting it.

**Acceptance Criteria:**
- The supervisor polls (freshness ~15m, doctor ~1h, sync ~6h while running) and auto-repairs reversible `warn`/healable `fail` with no prompt. (job B2)
- Auto-heal succeeds on **≥ 90%** of known-parseable healable failures; unknown classes escalate rather than auto-act. (PROVISIONAL)
- Timers apply battery/metered backoff and coalesce (one invocation in flight).

---

**US-B11 (P1):** As Bob, when a non-security update lands while I have a host session live, I want it **deferred (not blocked)** until my session ends, so that a breaking change never lands mid-task.

**Acceptance Criteria:**
- Non-security materialize is deferred while a host session is active. (fixes A-H8)
- Security fixes are **not** deferred — they act immediately (see US-B17).
- A deferred update applies automatically once the session ends.

---

**US-B12 (P1):** As Bob, when I want to act, I want a dropdown with **plain actions** (Sync now, Repair, What changed, Add a skill, Sign in, Hosts ▸, Preferences, Quit), so that each does one clear thing.

**Acceptance Criteria:**
- Each menu action spawns a CLI verb with `--json`; the menu **never mutates state itself**.
- "What changed" surfaces `update --json` `changed[]` (adds/updates/prunes + security trailers).

---

### The Honest Interruption — asked only about my own data (job B4)

**US-B13 (P1):** As Bob, when the system genuinely needs *me*, I want to be asked **only about my own data** (commit dirty personal WIP before a sync; the one sign-in), so that the rare time it interrupts me, I pay attention.

**Acceptance Criteria:**
- Bob-facing prompts are limited to reversible-or-owned decisions about his own data. (invariant #5)
- A dirty personal tree is **never** touched; the prompt asks Bob to commit, it does not auto-resolve. (invariant #3)
- Bob-facing notification count trends toward zero over a month of use. (PROVISIONAL)

---

**US-B14 (P1):** As Bob, when an update prunes a tool I actually **used recently**, I want to be told ("a tool you used was removed"), so that I'm not left to discover it later.

**Acceptance Criteria:**
- A prune of a **recently-used** item notifies; a prune of a zero-usage item stays silent. (fixes A-H9)
- "Recently used" is defined by CLI-surfaced usage, not app-computed heuristics. <!-- TODO: confirm the recency window + usage source with WS-A/WS-F -->

---

**US-B15 (P1):** As Bob, when a held-major upgrade is pending, I want to see a **non-actionable "an update is waiting on IT,"** never a decision to approve, so that I'm not handed a choice I have no basis to make.

**Acceptance Criteria:**
- Bob's view of a held-major is informational only — no approve/unblock control exists. (fixes A-H11, Soul: OUT)
- The approval decision routes to IT centrally (see US-A09).

---

**US-B16 (P1):** As Bob, when I've denied the macOS notification permission, I want high-severity events to **fall back to opening the popover** and re-route safety events to IT, so that a denied prompt never silently kills the whole alert tier.

**Acceptance Criteria:**
- Denied notification state is detected; high-severity events open the popover as fallback. (fixes A-H10)
- Safety events additionally re-route to the IT `AdminContact` channel regardless of local notification state.

---

### The Trust Test — when something goes wrong (MTM-3, MTM-5)

**US-B17 (P0):** As Bob, when a security fix ships for an agent my personal override was shadowing, I want the override **auto-suspended** so the fixed version wins immediately (reversibly — I can re-affirm), so that my exposure is closed by an action, not by a notification I never see.

**Acceptance Criteria:**
- A `severity_trailer: security` + `shadowed_by` (stale override) is **auto-suspended + escalated to IT**, never notify-and-hope. (fixes A-C3)
- Suspension is reversible: Bob can re-affirm the override later.
- To Bob the message is quiet and past-tense ("kept you safe"); a Bob notification is **never** the sole control on a live exposure.
- **Auto-suspend coverage = 100%** (invariant — any miss is a Critical regression).

---

**US-B18 (P1):** As Bob, when Control Tower self-updates to a bundle that crashes on launch, I want the watchdog to **roll back and keep my working version**, so that I'm never left with a dead menu bar I can't recover without a terminal.

**Acceptance Criteria:**
- Rollback lives in the **stable watchdog**, not the new bundle; it gates promotion on an early liveness heartbeat. (fixes B-C3)
- No heartbeat → discard the bundle, keep current, mark the bad version poisoned, notify calmly ("kept your working version").
- `KeepAlive={SuccessfulExit:false}` + a circuit breaker prevent any crash-loop. (fixes B-C2)

---

### Clean Exit (job B5)

**US-B19 (P2):** As Bob, when I uninstall or leave, I want the app to **come off cleanly** with no orphaned login item or watchdog, so that I can trust nothing company-owned lingers.

**Acceptance Criteria:**
- A signed uninstaller runs `launchctl bootout` + `SMAppService.unregister()` + Keychain cleanup.
- The watchdog self-`bootout`s if its `Program` path goes missing (drag-to-Trash doesn't orphan). (fixes B-H2)

---

## Raj — IT / Admin Operator Stories

### Setup — stand up the org (job A1, MTM enabler)

**US-A01 (P1):** As Raj, when I stand up the ecosystem, I want a **guided seed generator** that authors `ecosystem.yml` and opens the PR, so that I never hand-write YAML.

**Acceptance Criteria:**
- The generator produces a valid `ecosystem.yml` (products, departments, pins, `auth`/`host`/`mirror`, `policy_signers`, telemetry) and opens a PR. (H1)
- No hand-YAML is required to reach a valid seed.

---

**US-A02 (P1):** As Raj, when I create org repos, I want **repo & access scaffolding** with a declared-repo existence check, so that a typo can't ship a 404 to the fleet.

**Acceptance Criteria:**
- Creates/verifies org + separate per-department repos; emits team/CODEOWNERS/branch-protection. (H2)
- A declared repo that does not exist is flagged **before** rollout, not discovered as a fleet false-Healthy.

---

**US-A03 (P1):** As Raj, when I set capability policy, I want a **guided policy editor that signs with a security key distinct from push authority**, so that policy integrity is enforced.

**Acceptance Criteria:**
- Policy is signed by an authorized signer; the signing key is distinct from push authority. (H3)

---

**US-A04 (P0):** As Raj, when I prepare a fleet deploy, I want an **MDM profile generator** that emits a ready-to-upload `.mobileconfig` (managed keys + login-item + notifications payloads) pre-filled with my org's values, so that every employee's wizard runs silent. *(P0 — this is what enables Bob's Silent First Light.)*

**Acceptance Criteria:**
- Emits one `.mobileconfig` for `dev.enac.controltower` complete-for-the-silent-path, plus login-item + notifications payloads. (H4)
- Uploading the single artifact to Jamf/Kandji/Intune makes managed wizards run with zero questions.

---

**US-A05 (P0):** As Raj, when I'm about to push to the fleet, I want a **red/green preflight** that validates the whole path before rollout, so that I catch a typo/missing key **before** the fleet breaks — not as a field false-Healthy. *(P0 — prevents the mis-provisioned Bob.)*

**Acceptance Criteria:**
- Preflight checks: seed parses, declared dept repos exist, policy signed, profile **complete-for-silent** (the A-C1/B-H4 check run proactively), foundation pin resolves, mirror reachable. (H5)
- Produces a red/green report IT reads before pushing; any red blocks a clean deploy.

---

**US-A06 (P0):** As Raj, when preflight is green, I want to **deploy one artifact** to my MDM and have the fleet self-provision, so that I never touch each machine. *(P0 — the mechanical completion of the silent-Bob path.)*

**Acceptance Criteria:**
- One signed app + one profile uploaded to the MDM results in silent self-provision across managed machines.
- No per-machine hand-configuration is required.

---

### Operate — watch the fleet (job A2)

**US-A07 (P0):** As Raj, when employees' machines drift, fall behind, or lose auth, I want a **fleet dashboard** showing healthy / stuck / behind / needs-auth at a glance, so that I trust the fleet without waiting for Bob to call. *(P0 — closes the ecosystem's named observability gap.)*

**Acceptance Criteria:**
- The dashboard renders sync health, drift, auth-expiry, version skew, usage/adoption. (G3)
- An admin can distinguish a healthy Mac from a stuck one **at a glance** (survey target ≥ 95% agree — PROVISIONAL).
- Dashboard state rests on honest CLI-parsed states (no false-Healthy can appear).

---

**US-A08 (P1):** As Raj, when the foundation publishes a new locked SHA, I want a **version-skew panel** showing fleet convergence, so that I can see who's behind.

**Acceptance Criteria:**
- The panel shows the fraction of the fleet on the current locked SHA.
- Target: **≥ 90%** on-current within one sync cadence (~6h) of publish. (PROVISIONAL)

---

### Govern — decisions that need my authority (job A3, MTM-4)

**US-A09 (P1):** As Raj, when a held-major upgrade is pending, I want it to **route to my dashboard as an actionable item**, so that I decide with the authority Bob lacks.

**Acceptance Criteria:**
- Held-majors reach IT centrally (approver authority declared in `ecosystem.yml`); Bob sees only the non-actionable "waiting on IT." (fixes A-H11)
- An un-acted Bob-actionable item (backup-missing, re-auth) **time-boxes** to IT rather than degrading silently forever. (fixes A-H13)

---

**US-A10 (P1):** As Raj, when a capability-policy conflict occurs, I want it in my **action log only**, so that Bob is never notified about something he can't action.

**Acceptance Criteria:**
- Policy denials/conflicts route to the IT action log, never a Bob notification. (fixes A-M15)

---

**US-A11 (P0):** As Raj, when a safety-relevant event fires (sig-fail, auth-revoked, policy-conflict, stalled-onboarding, persistence-disabled, notifications-off), I want it to reach a **live IT channel on-by-default for managed machines**, so that "IT notified" is never a no-op. *(P0 — this makes the security guarantee real, MTM-3.)*

**Acceptance Criteria:**
- Safety escalation is **split from analytics** and on-by-default for managed machines via a **mandatory** `AdminContact`. (fixes A-C5)
- Signals are content-free (no personal data).
- **100%** of emitted safety signals reach the live channel (invariant — a miss is a Critical regression).

---

**US-A12 (P1):** As Raj, when a machine's login item or notifications get disabled, I want that **detected and escalated**, so that a silently-off background agent isn't mistaken for a powered-off Mac.

**Acceptance Criteria:**
- `SMAppService.status == .requiresApproval` / disabled login item is detected and surfaced as "persistence disabled" to IT. (fixes B-H3)
- A managed login-item MDM payload makes the item non-toggleable on managed fleets. (fixes B-H3)

---

### Offboard — reliable removal (job A4)

**US-A13 (P0):** As Raj, when an employee leaves, I want deprovision to be **MDM-native + server-side token revocation**, so that company access is revoked even if the employee trashes the app or stays offline. *(P0 — the "no secret ever materialized" guarantee.)*

**Acceptance Criteria:**
- Only an explicit `Deprovisioned=true` (never mere profile removal) triggers a wipe. (fixes B-M1)
- Server-side token revocation means the next online `copilot update` fails closed and wipes even if the app was trashed. (fixes A-C4)
- Honest boundary stated: an offline/powered-off machine can't be remotely wiped — the guarantee is "no secret materialized," not "exfiltration undone."
- `secrets_touched == 0` in the deprovision result.

---

**US-A14 (P1):** As Raj, when a deprovision fires, I want a **soft-then-hard two-phase** with a grace window, so that an accidental flip is recoverable without a re-clone.

**Acceptance Criteria:**
- Deprovision is debounced over a settling window; clones are quarantined for a grace window before hard wipe. (fixes B-M2)
- A flip-back within the grace window restores without a re-clone.

---

### Audit (job A5)

**US-A15 (P1):** As Raj, when my security team reviews what the always-on agent did, I want a **content-free, tamper-evident action log anchored to the org endpoint**, so that I can prove every auto-pull was visible, verified, and policy-bounded.

**Acceptance Criteria:**
- A hash-chained action log is anchored to the org endpoint so truncation is server-detectable. (G4/B-L2)
- The log is content-free (no personal item names, no file contents).

---

**US-A16 (P1):** As Raj, when I stand up the ecosystem, I want a **complete documentation set** (quickstart, per-MDM deploy guides, config reference, security-&-trust doc, ops/offboarding runbook), so that I can deploy from docs alone.

**Acceptance Criteria:**
- The doc set is versioned in the public repo and covers Jamf/Kandji/Intune. (H6)
- Target: **≥ 90%** of setups complete unaided (no support escalation). (PROVISIONAL)

---

## Pablo — Ecosystem Owner Stories

**US-O01 (P0):** As Pablo, when I ship a `security:`-trailered fix that a personal override shadows, I want the vulnerable version **auto-suspended fleet-wide (reversibly)**, so that the fix wins immediately without depending on any user noticing a notification. *(The system side of US-B17 / MTM-3, job O1.)*

**Acceptance Criteria:**
- Fleet-wide, a shadowing override is auto-suspended the moment the fix is seen; IT is escalated in parallel. (fixes A-C3)
- An `urgent-since` marker can override battery/metered backoff for the security case. (A-M16) <!-- TODO: confirm urgent-revocation propagation mechanism — freshness-poll floor vs. publish webhook (architecture §11 open decision #2) -->

---

**US-O02 (P1):** As Pablo, when an enterprise security team audits the always-on agent, I want it to be **open-source, reproducibly built, and two-of-N signed**, so that the whole ecosystem is adoptable at all.

**Acceptance Criteria:**
- Pure OSS, free forever; no closed component, no paid tier (Soul: The Ledger is OUT).
- Releases use **two-of-N signing** (or a transparency-log witness) with separate key custody. (G4/B-M4) <!-- TODO: signing custody — who holds the second key (architecture §11 open decision #1) -->

---

**US-O03 (P1):** As Pablo, when the agent runs, I want it to use the **same pipeline with zero bypass flags**, so that it is provably *safer than* a human running `copilot update` by hand.

**Acceptance Criteria:**
- No `--skip-verify` / `--force` path exists anywhere in the codebase (CI entitlement + preference lint). (Soul: The Convenience Backdoor is OUT)
- Every auto-pull is visible (what-changed), verified (same gate), policy-bounded, auditable.

---

**US-O04 (P0):** As Pablo, when config is read, I want **security-sensitive keys honored only from the forced/managed domain**, so that a user-domain preference-write can't repoint the update feed into a supply-chain RCE. *(P0 — a Critical security invariant.)*

**Acceptance Criteria:**
- `UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned` read via `CFPreferencesAppValueIsForced`. (fixes B-C5)
- A user-domain value for those keys is **ignored** in favor of the compiled-in default and **logged as a tamper event**.
- Trust roots (minisign pubkey + default feed) are compiled-in code, not config.

---

**US-O05 (P0):** As Pablo, when Control Tower renders any state, I want it to **parse the CLI's verdict and never compute one**, so that there is never a second, wrong source of truth. *(P0 — the inviolable invariant.)*

**Acceptance Criteria:**
- **Zero** resolution/health/signature/wipe logic in the app codebase (code-review gate every release). (O3)
- Materialized content matches CLI-computed winning layer 100% (provenance diff vs. `resolve --explain --json`).
- If Control Tower vanished, the CLI would still be correct.

---

**US-O06 (P0):** As Pablo, when the CLI schema drifts or a field is missing, I want the app to **fail closed**, so that schema drift can never read as a silent security bypass ("green over red"). *(P0.)*

**Acceptance Criteria:**
- Schema gating is **bidirectional** (min/max_schema): a schema older than the floor is as fatal as one newer. (fixes B-H6)
- Missing security fields (`destructive`/`signed`/`severity`) are treated as destructive/unsigned/fail, never safe.
- The `--json` contract CI test is **100% green** on every CLI release. (A6)
- The app parses the `--json` contract, never screen-scrapes human CLI prose (Soul: OUT).

---

**US-O07 (P1):** As Pablo, when telemetry flows to an IT dashboard, I want a **personal item name to be un-emittable by construction**, so that observability never becomes surveillance.

**Acceptance Criteria:**
- `machine_id = hmac(hardware_uuid + posix_uid, per-install-random-salt)` — per-user, non-reversible. (fixes B-H5)
- Usage emits **only** items whose CLI-computed winning layer ∈ {org, dept, foundation}; a personal name is un-emittable. (G2)
- Telemetry is opt-in, org-scoped (endpoint in `ecosystem.yml`, never ENAC).

---

## Jane / Sam — Developer-Contributor Stories (do-no-harm)

**US-D01 (P1, do-no-harm):** As a developer, when Control Tower supervises the same pipeline I run by hand, I want my direct `copilot update` / `resolve --explain` workflow to keep working **untouched**, so that I keep my terminal habits without the GUI double-writing my tree.

**Acceptance Criteria:**
- CLI-side `flock` on `copilot.lock` means no process arrangement double-writes; concurrent invocations serialize with no torn tree. (fixes B-C1)
- A dirty personal tree is **never** touched. (invariant #3)
- Success = the developer does not notice Control Tower at all.

---

## Story Priority Matrix

| ID | Story | Persona | Priority | Depends On |
|----|-------|---------|----------|------------|
| US-B01 | Silent managed first-run | Bob | P0 | US-A04, US-O06 |
| US-B02 | Unmanaged ≤3-question wizard | Bob | P0 | US-O06 |
| US-B03 | Fail-closed IT-config-incomplete | Bob | P0 | US-A11 |
| US-B04 | Waiting-for-network first-run | Bob | P0 | US-B07 |
| US-B05 | Resume interrupted setup headlessly | Bob | P0 | US-B01 |
| US-B06 | Teach panel / cheat sheet | Bob | P1 | US-B01 |
| US-B07 | Honest icon, never false-Healthy | Bob | P0 | US-O05, US-O06 |
| US-B08 | Status names the failing host | Bob | P0 | US-B07 |
| US-B09 | Distinct honest holding states | Bob | P0 | US-B07 |
| US-B10 | Auto self-heal reversible drift | Bob | P0 | US-B07 |
| US-B11 | Session-active backoff (non-security) | Bob | P1 | US-B10 |
| US-B12 | Dropdown actions spawn CLI verbs | Bob | P1 | US-B07 |
| US-B13 | Asked only about own data | Bob | P1 | US-B10 |
| US-B14 | Notify on prune of recently-used item | Bob | P1 | US-B12 |
| US-B15 | Non-actionable "waiting on IT" | Bob | P1 | US-A09 |
| US-B16 | Notification-denied fallback | Bob | P1 | US-A11 |
| US-B17 | Security-shadow auto-suspend (Bob view) | Bob | P0 | US-O01, US-A11 |
| US-B18 | Bad self-update rollback | Bob | P1 | US-B01 |
| US-B19 | Clean uninstall, no orphans | Bob | P2 | — |
| US-A01 | Guided seed generator | Raj | P1 | — |
| US-A02 | Repo & access scaffolding | Raj | P1 | US-A01 |
| US-A03 | Capability-policy authoring + signing | Raj | P1 | US-A01 |
| US-A04 | MDM profile generator | Raj | P0 | US-A01 |
| US-A05 | Red/green preflight | Raj | P0 | US-A02, US-A03, US-A04 |
| US-A06 | Deploy one artifact → fleet self-provision | Raj | P0 | US-A05 |
| US-A07 | Fleet dashboard | Raj | P0 | US-O07 |
| US-A08 | Version-skew panel | Raj | P1 | US-A07 |
| US-A09 | Held-major routes to IT | Raj | P1 | US-A07 |
| US-A10 | Policy conflicts → IT action log | Raj | P1 | US-A11 |
| US-A11 | Safety escalations reach live IT channel | Raj | P0 | US-A04 |
| US-A12 | Persistence/notifications-off detection | Raj | P1 | US-A11 |
| US-A13 | MDM-native deprovision | Raj | P0 | US-A04 |
| US-A14 | Soft-then-hard wipe + grace | Raj | P1 | US-A13 |
| US-A15 | Content-free tamper-evident audit log | Raj | P1 | US-A11 |
| US-A16 | Documentation set | Raj | P1 | US-A01…A05 |
| US-O01 | Security auto-suspend fleet-wide | Pablo | P0 | US-A11 |
| US-O02 | OSS + reproducible + two-of-N signing | Pablo | P1 | — |
| US-O03 | Zero bypass flags — safer than manual | Pablo | P1 | US-O05 |
| US-O04 | Security keys only from forced domain | Pablo | P0 | — |
| US-O05 | Parse-never-compute | Pablo | P0 | US-O06 |
| US-O06 | Bidirectional schema gate, fail-closed | Pablo | P0 | — (WS-A contract) |
| US-O07 | Personal name un-emittable | Pablo | P1 | — |
| US-D01 | Direct CLI workflow untouched | Jane/Sam | P1 | US-O06 (WS-A flock) |

## Story Summary

| User Type | P0 Stories | P1 Stories | P2 Stories | Total |
|-----------|-----------|-----------|-----------|-------|
| Bob (Operator) | 10 | 8 | 1 | 19 |
| Raj (IT / Admin) | 6 | 10 | 0 | 16 |
| Pablo (Ecosystem owner) | 4 | 3 | 0 | 7 |
| Jane / Sam (Contributor) | 0 | 1 | 0 | 1 |
| **Total** | **20** | **22** | **1** | **43** |

## Critical View Coverage (touchpoints → stories)

| Touchpoint (journey rank) | Covered by |
|---------------------------|------------|
| Menu-bar icon + one-line status sentence | US-B07, US-B08, US-B09 |
| First-run wizard (silent / ≤3-Q) | US-B01, US-B02, US-B03, US-B04, US-B05, US-B06 |
| Dropdown menu | US-B12, US-B14, US-B15 |
| Notifications (rare) | US-B13, US-B14, US-B16, US-B17 |
| Admin-mode window / fleet dashboard | US-A01–A08, US-A15 |
| MDM push / IT safety channel | US-A04, US-A06, US-A11, US-A13 |

## Explicitly OUT of scope (Soul Feature Filter — no stories)

Per `SOUL.md` §5 Case Law, the following are ruled OUT and deliberately have **no** user story:
offline health scoring; in-app AI chat / conversational health surface; Bob approving or self-unblocking a
held/blocked update; `--force`/`--skip-verify` "unstick it" mode; `KeepAlive=true`; reading
`UpdateFeedURL`/mirror from the user preference domain; a "make it Healthy anyway" override;
screen-scraping human CLI output; any paid tier / hosted dashboard / closed component.

---

**Related:** [Use Cases & Scenarios](20-use-cases-and-scenarios.md) | [Acceptance Criteria](30-acceptance-criteria.md) | [JTBD](../02-service-design/30-jtbd.md) | [Moments That Matter](../02-service-design/40-moments-that-matter.md)
