> **Superseded framing.** This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of "product" to mean a CSE tool are superseded. The corrected model is in `docs/reference/copilot-solutioning-ecosystem.md`; the decisions are in `docs/reference/cse-alignment-decisions.md`.

# Use Cases & Scenarios

> **Provenance.** End-to-end scenarios translated from the journey maps (`02-service-design/20-journey-maps.md`),
> moments that matter (`40-moments-that-matter.md`), the PRD workstream tasks (`02-prd/prd.md`), and the
> architecture's routing ladder + exit-code/degrade behavior (`01-architecture/architecture.md` §5–§9,
> `cli-contract.md`). The **edge cases and error scenarios are the red-team failure modes** — those are
> the moments where trust is won or lost, so they are the richest material for testing and prototyping.
> Each scenario is testable and traces to its user stories. Genuine unknowns marked `<!-- TODO -->`.

---

## End-to-End Scenarios

### Scenario 1 — The Silent First Light (managed, happy path)
*Covers US-B01, US-B05, US-B07; MTM-1. Primary hero flow.*

**Trigger:** IT has pushed the signed app + a complete `.mobileconfig` to a managed Mac via Jamf/Kandji/Intune. Bob logs in (or double-clicks once).

**Steps:**
1. The app launches as an Accessory (menu-bar) process; installs the login-item + crash-watchdog at the **first** wizard phase and persists a checkpoint.
2. It reads `dev.enac.controltower` from the forced/managed domain and **schema-validates** the profile before entering silent mode.
3. All required keys present + typed → silent mode. Bob watches a progress bar; **he is asked nothing.**
4. The supervisor runs the Ring-1 phases via `copilot doctor --bootstrap` / `derive` / `update` (host detection → clone → materialize → verify), each spawning a CLI verb with `--json`.
5. On success the icon renders **Healthy** (parsed from `doctor --json status: healthy`); a working host (Claude and/or Codex) is present.
6. The teach panel offers a cheat sheet + "add your first skill" + a backup (US-B06).

**Outcome:** Bob has a working, team-scoped partner. He never saw a terminal, answered no questions, and the icon is an honest Healthy. (perf: p90 push→terminal-state ≤ 10 min — PROVISIONAL)

---

### Scenario 2 — Unmanaged setup (≤3 questions)
*Covers US-B02, US-B06.*

**Trigger:** Bob (or a solo user) double-clicks the app on an unmanaged Mac with no `.mobileconfig`.

**Steps:**
1. Welcome → host detection probe. If both/neither host present, ask which (question 1); else derive.
2. Sign-in via GUI device flow — show 8-char code, open browser (question 2). No terminal.
3. Company suggested + confirmed; department pick-list from Teams API (question 3).
4. Products pre-checked from `ecosystem.yml`; repos pulled; materialize + verify; teach panel.

**Outcome:** A working partner after ≤3 answers; OS/arch, prereqs, repo URLs, product set, git identity all derived.

---

### Scenario 3 — Invisible steady-state self-heal
*Covers US-B10, US-B11, US-B12; job B2.*

**Trigger:** Time passes; the supervisor polls (freshness ~15m, doctor ~1h, sync ~6h while running).

**Steps:**
1. `freshness --json` reports `stale: true` (fleet moved to a new locked SHA).
2. The supervisor runs `update --json`; reversible drift is auto-repaired within policy (AUTO-ACT lane).
3. If a host session is live and the change is **non-security**, materialize is **deferred** (not blocked) until the session ends (US-B11).
4. Bob is not interrupted; the icon stays solid (or briefly shows the animated Syncing ring, then Healthy).

**Outcome:** The machine stays current and healed on its own. Auto-heal succeeds on ≥90% of known-parseable healable failures (PROVISIONAL); unknown classes escalate rather than auto-act.

---

### Scenario 4 — The Fix That Acts Itself (security shadow)
*Covers US-B17, US-O01, US-A11; MTM-3. The Critical trust moment.*

**Trigger:** Pablo publishes a `security:`-trailered fix upstream for an agent Bob overrode months ago and forgot. Bob has Focus on, never granted notification permission, hasn't opened the dropdown in weeks.

**Steps:**
1. `update --json` returns a `changed[]` entry with `severity_trailer: security` and `shadowed_by: <bob's stale override>`.
2. The escalation router classifies: reversible + Bob-can't-judge ⇒ **AUTO-ACT**. It **auto-suspends** the override so the fixed version wins immediately.
3. In parallel, a content-free safety signal reaches the IT `AdminContact` channel (on-by-default, managed).
4. To Bob (if/when he looks), the message is quiet + past-tense: "kept you safe." Bob can re-affirm his override later.

**Outcome:** The exposure window is closed by an action, not a hope. A Bob notification is never the sole control. Auto-suspend coverage = 100% (invariant).

---

### Scenario 5 — Org standup + fleet deploy (Admin)
*Covers US-A01–A07, US-A16; job A1/A2. The enabler flow.*

**Trigger:** Earl opens Admin mode to stand up the ecosystem for his org.

**Steps:**
1. **Seed generator** authors `ecosystem.yml` and opens a PR (no hand-YAML).
2. **Repo & access scaffolding** creates/verifies org + per-dept repos; emits team/CODEOWNERS/branch-protection; runs the declared-repo existence check.
3. **Capability-policy** editor signs with the security key (distinct from push).
4. **MDM profile generator** emits one `.mobileconfig` (managed keys + login-item + notifications payloads), pre-filled.
5. **Preflight** produces a red/green report: seed parses, dept repos exist, policy signed, profile complete-for-silent, pin resolves, mirror reachable. All green.
6. Earl uploads one app + one profile to the MDM; the fleet self-provisions (Scenario 1 at scale).
7. Earl watches the **fleet dashboard** — healthy / stuck / behind / needs-auth at a glance.

**Outcome:** The org is stood up and deployed from Admin mode + docs alone; the observability gap is closed. Target ≥90% of setups complete unaided (PROVISIONAL).

---

### Scenario 6 — Offboarding a leaver
*Covers US-A13, US-A14; job A4, MTM (clean exit).*

**Trigger:** HR marks an employee as departed; Earl sets `Deprovisioned=true` in the managed profile.

**Steps:**
1. Server-side token revocation fires (the real backstop).
2. The MDM-run `copilot deprovision <org> --json` executes as its own managed agent; only the explicit `Deprovisioned=true` triggers it (not profile removal).
3. **Soft phase:** clones are quarantined for a grace window (a flip-back restores without a re-clone).
4. **Hard phase:** after debounce/grace, materialized company content is wiped; `secrets_touched == 0`.
5. If the machine is offline/trashed-app, the next online `copilot update` fails closed and wipes.

**Outcome:** Company access is revoked reliably even if the employee trashes the app or stays offline. Honest boundary: an offline/powered-off machine can't be remotely wiped — the guarantee is "no secret ever materialized," not "exfiltration undone."

---

### Scenario 7 — The Watchdog Catches a Bad Update
*Covers US-B18; MTM-5.*

**Trigger:** Control Tower self-updates overnight; the new bundle panics on launch before the webview mounts.

**Steps:**
1. The stable watchdog (never self-updated) staged the new bundle and verified it was stapled offline before promoting.
2. It launches the new bundle with `--self-test` and waits for an **early liveness heartbeat file**.
3. No heartbeat → discard the new bundle, keep the current working version, mark the bad version poisoned, notify calmly.
4. `KeepAlive={SuccessfulExit:false}` + a circuit breaker (N non-zero exits → stop relaunching, surface "reinstall") prevent any crash-loop.

**Outcome:** Bob sees nothing, or a calm "kept your working version." No dead menu bar, no crash-loop, no terminal needed.

---

## Edge Cases & Error Scenarios
*Each row is a red-team failure mode — the priority test material.*

| # | Scenario | Trigger | Expected Behavior | Stories / Findings |
|---|----------|---------|-------------------|--------------------|
| E1 | **Missing MDM key + silent wizard** | `DisableWizard=true` but a required key (`Department`/`OrgSlug`/`EcosystemSeedURL`) absent/malformed | Fail **closed** into **IT-config-incomplete** (wrench badge) + IT escalation; **never** guess, hang, or show Healthy. *Absent* retries over a settling window; *present-but-invalid* → immediate "IT config error: `<key>`" | US-B03 / A-C1, B-H4 |
| E2 | **Offline first-run** | New laptop on home wifi; foundation-only clone completes | **Waiting-for-network** (clock badge), never Healthy, never a scary error; supervisor completes company clones on reconnect | US-B04 / A-H7 |
| E3 | **Seed not yet published** | IT shipped the app before `ecosystem.yml` exists | Hold in **Waiting-for-network**, distinguished from "solo user" via managed `EcosystemSeedURL`; complete when seed appears — never false-Healthy | US-B04 / A-H12 |
| E4 | **Quit mid-wizard** | Bob quits after clone but before materialize | Resume **headlessly** from the persisted checkpoint on next login (login-item + watchdog installed at first phase) | US-B05 / A-H6 |
| E5 | **Gatekeeper kills the vendored CLI** | Vendored `copilot`/`cc` carries quarantine → spawn dies | Cross-repo signed+notarized+universal binaries at pinned SHA; `.pkg` postinstall de-quarantine; a `cli-spawnable` doctor check surfaces it as a **named** finding, not a generic red | US-O03 / A-C2 |
| E6 | **Schema drift shows green over red** | A CLI `--json` field missing, or schema newer/older than app range | Bidirectional min/max_schema gate; missing security fields **fail closed to fail**; in-app "versions don't match — click to update" (never "run doctor in a terminal") | US-O06 / B-H6 |
| E7 | **User-domain preference-write attack** | `defaults write dev.enac.controltower UpdateFeedURL <evil>` in the user domain | Value **ignored** in favor of the compiled-in default (read via `CFPreferencesAppValueIsForced`) + **logged as a tamper event** | US-O04 / B-C5 |
| E8 | **Security shadow Bob never sees** | Override shadows a `security:` fix; Focus/DND on, notifications denied | **Auto-suspend** the override + escalate to IT — never notify-and-hope | US-B17, US-O01 / A-C3 |
| E9 | **Un-wipeable leaver** | Bob trashes the app / stays offline after `Deprovisioned=true` | Server-side token revocation + MDM-run deprovision; next online `update` fails closed + wipes; honest "no secret materialized" boundary | US-A13 / A-C4 |
| E10 | **Held-major dumped on Bob** | A major-version bump awaits a decision | Route to **IT centrally**; Bob sees a non-actionable "waiting on IT"; **no** approve/unblock control exists for Bob | US-B15, US-A09 / A-H11 |
| E11 | **A used skill silently pruned** | A daily-used tool is pruned by an update | Notify ("a tool you used was removed") on a prune of a **recently-used** item; zero-usage prunes stay silent | US-B14 / A-H9 |
| E12 | **Notification permission denied** | Bob denied the macOS prompt | Detect denied state; high-severity → open popover fallback; safety events re-route to the IT channel; managed fleets force-authorize via notifications profile | US-B16 / A-H10 |
| E13 | **Login item toggled off** | Bob/naive act disables the SMAppService login item | Managed login-item MDM payload (non-toggleable) + detect `.requiresApproval` + emit "persistence disabled" to IT (not indistinguishable from a powered-off Mac) | US-A12 / B-H3 |
| E14 | **Bad self-update crash-loops the menu bar** | A bundle crashes on launch | Watchdog-owned rollback gated on early liveness heartbeat; `KeepAlive={SuccessfulExit:false}` + circuit breaker | US-B18 / B-C2, B-C3 |
| E15 | **Dual-writer race** | A stray second instance / manual CLI run / fast-user-switching writes concurrently | CLI-side `flock` on `copilot.lock` serializes all writers; a global per-host mutex drains pending syncs before `deprovision`; no torn `.claude/` tree | US-D01 / B-C1 |
| E16 | **Bob-actionable alert nudged once then silent forever** | Backup-missing / re-auth left un-acted past a deadline | **Time-boxed escalation** to IT ("Bob's Mac hasn't been backed up in 7 days"); never silent-forever degradation | US-A09 / A-H13 |
| E17 | **Safety escalation reaches no one** | Escalation gated behind off-by-default analytics | Safety channel **split from analytics** and on-by-default for managed via mandatory `AdminContact`; "IT notified" is never a no-op | US-A11 / A-C5 |
| E18 | **Breaking change lands mid-session** | Non-security materialize arrives while a host session is live | **Session-active backoff** — defer (not block) until the session ends; security fixes are exempt | US-B11 / A-H8 |
| E19 | **Blocked update Bob can't self-unblock** | An update is `blocked[]` in `update --json` | Bob has **no** self-unblock control (Soul: OUT); it routes to IT; Bob's view is informational | US-B15 / Soul §5 |
| E20 | **Telemetry name-leak attempt** | A personal item name would be emitted to the dashboard | Un-emittable **by construction**: usage emits only items whose CLI-computed winning layer ∈ {org,dept,foundation}; `machine_id` is a per-user salted HMAC | US-O07 / B-H5 |
| E21 | **Both hosts, one broken** | Claude healthy, Codex sign-in expired | Status is worst-wins but **names the failing host** ("Codex needs sign-in; Claude is fine"); per-host transactional lock stays consistent | US-B08 / A-M14 |
| E22 | **Stale auth token** | A required layer's auth expired/revoked | **Signed-out** state (key badge); Bob is asked for the one sign-in (his own data); if it's a machine credential, escalate to IT | US-B09, US-B13 / §2 |

---

## Exit-Code / Degrade Behavior (from architecture §6)

| CLI exit | Meaning | Control Tower behavior |
|----------|---------|------------------------|
| `0` | Clean (all checks pass) | Render **Healthy** (only path to Healthy) |
| `1` | Any check `fail` | Render the specific failing state (Needs-attention / Signed-out), naming the host; auto-repair the healable lane |
| `2` | Env error (CLI not runnable) | Render an honest error state (e.g. `cli-spawnable` finding), **never** Healthy; drive in-app "click to update" |
| schema out of range | min/max_schema violation | Fail closed; in-app "versions don't match — click to update," never "run doctor in a terminal" |
| missing security field | absent `destructive`/`signed`/`severity` | Treat as destructive/unsigned/fail — never safe/green |

---

## Critical View Scenarios (feed the design challenge / prototype)

| CV | View | Scenarios it must demonstrate |
|----|------|-------------------------------|
| **CV-1** | **Menu-bar icon + status sentence** (highest-impact touchpoint) | Healthy (solid); IT-config-incomplete (wrench, E1); Waiting-for-network (clock, E2); Signed-out (key, E22); Needs-attention naming the failing host (E21); Syncing ring (S3). **Must have no path to fabricate Healthy.** |
| **CV-2** | **First-run wizard** | Silent managed progress bar (S1); ≤3-question unmanaged (S2); fail-closed IT-config-incomplete (E1); Waiting-for-network hold (E2); resume-after-quit (E4); teach panel (S1.6). |
| **CV-3** | **Dropdown menu + "What changed" panel** | Sync now / Repair / Sign in actions (S3); the security-shadow past-tense "kept you safe" (S4); prune-of-used-item notice (E11); non-actionable "waiting on IT" (E10). |
| **CV-4** | **Admin fleet dashboard** | Healthy/stuck/behind/needs-auth at a glance (S5.7); version-skew panel (US-A08); a held-major awaiting IT approval (E10); a persistence-disabled machine (E13). |
| **CV-5** | **Admin setup flow + preflight** | Seed generator → scaffolding → MDM profile generator → red/green preflight (S5.1–5.5), including a **red** preflight catching a declared-repo 404 (US-A02) before rollout. |

---

**Related:** [User Stories](10-user-stories.md) | [Acceptance Criteria](30-acceptance-criteria.md) | [Journey Maps](../02-service-design/20-journey-maps.md) | [Moments That Matter](../02-service-design/40-moments-that-matter.md)
