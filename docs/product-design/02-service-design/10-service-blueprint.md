# Service Blueprint

> **Provenance.** Grounded synthesis from `20-journey-maps.md`, `architecture.md` §2–§9,
> `cli-contract.md` (WS-A), the **primary-evidence owner interview** (2026-07-06,
> `01-research/10-interviews/01-interview-self.md`; `scratchpad/interview-ground-truth.md`), and the
> two red-teams. Backstage is given equal weight to frontstage — for this product it is where nearly
> every failure originates, because Control Tower deliberately owns *no* intelligence: the backstage is
> the `copilot`/`cc` CLI, `flock`, the `launchd` watchdog, MDM forced-domain config, the minisign trust
> chain, the telemetry sink, and — new since the interview — the **write/publish path** (Obsidian →
> push → cadence sync). Prerequisite: journey maps complete.
>
> **The reframe (primary evidence, 2026-07-06).** The soul is **democratization: give a non-technical
> person the AI superpowers of a deeply technical one, safely enough to run unattended.** The interview
> added a **third actor between Pablo (foundation) and Bob (consumer): the trained early-adopter AUTHOR**
> (org/department writer). This blueprint now carries a **Write/Publish lane** for that actor alongside
> the Deploy/Consume spine, plus its new failure points (merge-conflict, credentials-carrying, the
> personal↔shared boundary).
>
> **Evidence stamps.** **GROUNDED** (Bob's psychology) · **OBSERVED** (Pablo's lived hand-sync pain) ·
> **MODEL-IN-HEAD** (the multi-writer authoring lane — never run with >1 writer) · **HYPOTHESIS** (the
> IT/Admin lane — no real operator) · **UNSOLVED** (merge-conflict resolution, credentials-carrier).
>
> **The five invariants are backstage constraints, not aspirations:**
> (1) **Parse, never compute** — the app calls CLI verbs and renders; no resolution/health/signature/
> wipe logic lives in-app. (2) **Single process** — one signed binary; `launchd` is crash-only; the
> **CLI self-serializes via `flock`**. (3) **Never-destroy** — re-materialize freely, never touch a
> dirty personal tree. (4) **Security inherited, never weakened** — no `--skip-verify`/`--force`;
> security keys only from the forced/managed domain. (5) **Route by actor-competence × reversibility.**
>
> > **⚠ Flagged backstage risk — writable tiers vs. never-destroy.** The Write/Publish lane introduces
> > *writable, collaborative* org/department tiers. This **strains invariant #3** ("re-materialize
> > freely, never touch a dirty tree") and the *read-only mirror* model: a mirror the author can *write*
> > is no longer read-only, and a cadence sync that carries a colleague's change can collide with local
> > edits (see MTM-7 / F15). Trained-few-writers-first shrinks the blast radius but does **not** remove
> > it. This is an **open architecture/security problem** (`interview-ground-truth.md` §6), stamped
> > MODEL-IN-HEAD, not a settled design.

---

## Blueprint spine (stages)

```
S1 Deploy (IT)  →  S2 Provision (Bob)  →  S3 First Partner  →  S4 Steady-State  →  S5 Change/Heal  →  S6 Escalate  →  S7 Deprovision
```

---

## Customer Actions

| Stage | Bob (Operator) | Earl (IT / Admin) |
|-------|----------------|-------------------|
| **S1 Deploy** | — | Authors seed in the generator; generates + preflights the MDM profile; uploads one `.mobileconfig` to Jamf/Kandji/Intune |
| **S2 Provision** | Double-clicks once (or nothing, managed); approves the one browser sign-in; confirms company/team if unmanaged | Watches the fleet begin to report in |
| **S3 First Partner** | Reads the one-line cheat sheet; optionally adds a first skill / accepts backup offer | — |
| **S4 Steady-State** | Glances at the icon; keeps working | Glances at the dashboard |
| **S5 Change/Heal** | Commits dirty WIP *only when asked*; otherwise nothing | — |
| **S6 Escalate** | Re-affirms a suspended override (rare); nothing else | Approves a held-major centrally; resolves a stuck machine |
| **S7 Deprovision** | (Leaves / uninstalls) | Sets explicit `Deprovisioned=true`; runs the signed uninstaller path via MDM |

> **A third actor — Ada (the trained early-adopter AUTHOR)** — sits between Pablo (foundation) and Bob
> (consumer) and runs a **separate lane**, not a column of S1–S7. Her actions (earn access → author in
> Obsidian → save → push → let the cadence carry it) are blueprinted in **[Write/Publish Lane](#writepublish-lane-author--ada)**
> below. Write access is **earned and gated**, small-then-growing. `> **Evidence: MODEL-IN-HEAD**`.

---

## Frontstage (Line of Visibility)

| Stage | What the user sees |
|-------|---------------------|
| **S1** | Admin-mode window: guided seed editor → repo/access scaffolding → capability-policy signer → **MDM profile generator** → red/green **preflight report** → per-MDM runbook. |
| **S2** | Silent progress bar (managed) *or* a ≤3-step wizard (host if ambiguous → device-flow 8-char code + browser → company/team). If a required managed key is missing: a distinct **"IT configuration incomplete — contact IT"** card, never a guess. |
| **S3** | Menu-bar icon goes **solid**; a short "teach" panel (cheat sheet + "add your first skill" + backup offer). |
| **S4** | Menu-bar icon + one-line status sentence that **names the failing host**; dropdown (Sync now · Repair · What changed · Add a skill · Sign in · Hosts ▸ · Preferences · Quit). Honest states: *Healthy / Syncing / Update-available / Waiting-for-network / Offline*. |
| **S5** | Usually **nothing** (auto-heal is invisible). A rare notification *only* when Bob is the sole competent actor ("commit your dirty work"; "a tool you used was removed"). |
| **S6** | Bob: a calm, non-actionable "an update is waiting on IT," or a silent auto-suspend he never notices. IT: an actionable dashboard row + a content-free safety signal on the `AdminContact` channel. |
| **S7** | Bob: "company content removed" (honest boundary if offline). IT: dashboard row transitions to deprovisioned; audit-log entry. |

---

## Backstage

*What runs behind the line of visibility. This is the product's substance — the app is a thin skin over it.*

| Stage | Backstage work | Invariant enforced |
|-------|----------------|--------------------|
| **S1** | Seed generator emits `ecosystem.yml` + opens a PR; repo/access scaffolding via `gh`; capability policy **signed with the security-team key** (distinct from push authority); MDM profile generator emits the `dev.enac.controltower` payload + managed login-item (`com.apple.servicemanagement`) + notifications (`com.apple.notificationsettings`) payloads; **preflight** runs the A-C1 completeness check, declared-dept-repo existence, policy-signer authorization, foundation-pin resolution, mirror reachability. | #4 (signing is authored, not weakened) |
| **S2** | Wizard drives `copilot doctor --bootstrap` phases P2–P10; **schema-validates the managed profile** (absent vs present-but-invalid vs valid; type-checks; settling window for partial MDM apply) → fail-closed *IT-config-incomplete*; installs SMAppService login item + `launchd` crash-watchdog + a persisted checkpoint at the **first** phase; GUI device-flow sign-in; `copilot derive` selects the `claude`/`codex` column; offline → foundation-only + *Waiting-for-network*. | #1, #4, (persistence at first phase = A-H6 fix) |
| **S3** | CLI materializes `.claude/` per host and verifies; Control Tower **parses** the result and renders — it never computes what materialized. | #1, #3 |
| **S4** | Single-process supervisor runs timer loops **while alive** (freshness `copilot freshness --json` ~15m, doctor ~1h, sync ~6h) with battery/metered backoff; each menu action spawns a CLI verb with `--json`; **status computed CLI-side**, parsed and projected worst-wins across hosts. **No headless daemon, no in-app fallback loop.** | #1, #2 |
| **S5** | `copilot update --json` returns `changed[]`; the **escalation router** classifies each by actor-competence × reversibility: AUTO-ACT (re-materialize, ff-pull, apply signed patches, defer non-security materialize while a host session is live, **auto-suspend a security-shadowing override**) / ESCALATE-IT / ASK-BOB. **CLI-side `flock` on `copilot.lock`** serializes every verb (a global per-host mutex so `deprovision` drains pending syncs); the app is *not* the lock. Never touches a dirty personal tree. | #1, #2, #3, #5 |
| **S6** | Held-majors + policy conflicts + signature failures + time-boxed un-acted Bob items → the mandatory `AdminContact` **safety channel** (content-free, on-by-default for managed), split from opt-in analytics; auto-suspend + parallel escalate for the security shadow. | #4, #5 |
| **S7** | Only an explicit `Deprovisioned=true` (never mere profile removal) triggers a debounced, **soft-then-hard** wipe via `copilot deprovision --json` (`secrets_touched` MUST be 0); real backstop is **server-side token revocation** (next online `update` fails closed + wipes) + an MDM-run `deprovision` agent; signed uninstaller runs `launchctl bootout` + `SMAppService.unregister()` + Keychain cleanup. | #3 (retains dirty work), #4 |

---

## Write/Publish Lane (Author — Ada)

> `> **Evidence: MODEL-IN-HEAD**` — this entire lane has **never been run with more than one writer.**
> It is the interview's new actor tier and the everyday-hero mechanism ("make a change once, never
> wonder whether it landed"), but its two hardest points — merge-conflict resolution and the
> credentials-carrier — are **UNSOLVED.** Design it, but do not let downstream over-trust it.

A parallel spine for the trained early-adopter author, sitting between Pablo (foundation) and Bob
(consumer). The consumer spine (S1–S7) *pulls*; this lane *pushes*, and the cadence sync is where the
two meet on every consumer machine.

```
W1 Earn access  →  W2 Author (Obsidian)  →  W3 Save & Push  →  W4 Cadence sync → every machine  →  W5 Collide/Resolve
```

| Stage | Ada (Author) — Customer Action | Frontstage (visible) | Backstage (CLI/git-owned) | Invariant / risk |
|-------|-------------------------------|----------------------|----------------------------|-------------------|
| **W1 Earn access** | Is granted **gated, earned** write access to an org/department repo (starts with a few innovators, grows with demand) | An access grant lands; her Obsidian vault gains a writable tier | IT/Pablo scaffolds the writable dept remote + push authority (distinct from the capability-policy signer); credential provisioned to her machine | #4 · **credentials-carrier UNSOLVED (F16)** |
| **W2 Author** | Opens the **tier-scoped Obsidian vault**, edits a skill/agent/Knowledge-Copilot doc/CLI integration — or has AI update it | The vault; a clear indicator of *which tier* she's editing (personal vs dept vs org) | Files live on disk in the tier's tree; **personal and shared are separate trees/remotes** so a personal artifact has no route upward | **#3 tension (writable tier)** · leakage wall (F17) |
| **W3 Save & Push** | Saves; triggers "publish" (a button, not a `git push` command) | A plain-language "publishing your change to *Finance*…" → "published"; **never** a Git terminal | `copilot publish --json` (or equivalent) commits + pushes to the *tier-correct* remote only; **fail-closed if the change touches a tier she can't write**; no personal content can be selected | #4 · #5 · leakage wall enforced by construction |
| **W4 Cadence sync → every machine** | Nothing — she's done; she does **not** babysit | On consumers: the change simply *appears* on the next cadence; the author gets a "landed on N machines" confirmation (closes the "did it land?" anxiety) | Every consumer's supervisor `freshness`→`update` pull carries it on cadence (~6h), deferring while a host session is live; **manual "sync now" is an escape hatch; per-minute refresh is explicitly wrong** | #1 · #2 · #5 |
| **W5 Collide/Resolve** | If a colleague edited the same file: sees a plain-language "keep both / choose" — **never** a Git conflict marker | A non-technical, side-by-side resolution surface, or (if it can't be made safe) an "held — escalated to an author" state | Conflict handled behind the scenes where non-overlapping; a true content collision is resolved with **no data loss and no Git literacy**, or escalated to a competent author — **never** lost | **#3 strained · MERGE-CONFLICT UNSOLVED (F15; MTM-7)** |

**How the two lanes meet:** W4 *is* Bob's Stage-4 steady-state from the other side — an authorized
change made once upstream appears on his machine on cadence, without touching his personal work. The
seam between "author pushes" and "consumer pulls" is where the **leakage wall (F17)** and **merge-
conflict (F15)** risks live, and where the writable-tier strain on never-destroy (invariant #3) is felt.

---

## Support Processes

*Systems, infrastructure, external dependencies — the substrate the backstage rides on.*

| Process | Role | Constraint (from the invariants / red-team) |
|---------|------|------------------------------------------------|
| **CLI `--json` contract (WS-A)** | The whole safety boundary — every consumed verb (`doctor`/`update`/`repair`/`resolve`/`deprovision`/`freshness`) emits versioned JSON with `schema_version` | Bidirectional `min/max_schema` gate; **missing security fields fail closed**; CI contract test green in the `copilot` repo. **Prerequisite for everything** (`cli-contract.md`). |
| **`flock` on `copilot.lock`** | CLI self-serialization across all verbs | The CLI is the lock, not the app — no process arrangement can double-write (B-C1). |
| **`launchd` crash-only watchdog** | Relaunch on crash only + own the self-update health gate/rollback | `KeepAlive={SuccessfulExit:false}`, `RunAtLoad=false`, **never `true`**; `ThrottleInterval` + circuit breaker; stable stub never self-updated (B-C2/B-C3). |
| **`SMAppService` login item** | Launch-at-login (one mechanism) | Managed login-item MDM payload makes it non-toggleable; detect `.requiresApproval` → emit "persistence disabled" to IT (B-H3). |
| **MDM forced/managed domain** (`dev.enac.controltower`) | Delivers org config + security keys + login-item + notifications payloads | Security keys (`UpdateFeedURL`, `FoundationMirror`, `EcosystemSeedURL`, `HTTPSProxy`, `GitHubHost`, `AuthMode`, `AllowSelfUpdate`, `Deprovisioned`) read **only** via `CFPreferencesAppValueIsForced`; user-domain values ignored + logged as tamper (B-C5). Trust roots are compiled-in code, not config. |
| **Minisign + two-of-N signing / transparency-log** | App self-update trust chain, independent of the Apple codesign chain | One popped key ≠ fleet RCE; codesign cert + minisign key in separate custody; staged rollout with anomaly-halt (B-M4). |
| **Cross-repo signed-CLI artifact contract** | `claude-copilot` CI publishes already-signed/notarized universal `copilot`/`cc` at a pinned SHA+version | Control Tower CI *verifies* (`codesign`, `spctl`), never re-signs; blocks release if the vendored CLI is below the compat floor (B-H1). |
| **Developer ID + notarize + staple** | Distribution (not Mac App Store — sandbox forbids spawning the CLI) | Userland-only entitlements; no admin, no privileged helper; per-`$UID` everything. |
| **Server-side token revocation** | The real deprovision backstop | Independent of the app existing/being online (A-C4). |
| **Opt-in, org-scoped telemetry sink → IT dashboard** | Closes the observability gap | `machine_id = hmac(hardware_uuid + posix_uid, per-install-random-salt)`; usage emits only CLI-verified `{org,dept,foundation}` items — a **personal name is un-emittable by construction** (B-H5). |
| **Mandatory `AdminContact` safety channel** | Content-free safety escalations | On-by-default for managed machines; split from analytics so "IT notified" is never a no-op (A-C5). |
| **Writable org/department remotes + gated push authority** | The Write/Publish lane's substrate | `> **MODEL-IN-HEAD**` — write access is *earned and gated* (few innovators, growing); push authority is distinct from the capability-policy signer; **breaks the read-only-mirror assumption** (invariant #3 tension). |
| **Personal↔shared tier separation** (distinct trees + remotes) | Makes the leakage wall structural | Personal-layer content has **no route** into a shared remote; the push path is tier-scoped and fails closed (leakage-wall guarantee; analogue of the *un-emittable-by-construction* telemetry, B-H5). |
| **Credentials-carrier through a pull-based model** | Delivers push/pull secrets when a company has **no cloud secret store** | `> **UNSOLVED (F16)**` — candidate is GitHub-as-carrier, but *how, safely* is open. Gates the whole Write/Publish lane. Route to security/threat-model (`interview-ground-truth.md` §10). |
| **Non-technical merge-conflict resolution** | Resolves a two-author collision with no Git literacy | `> **UNSOLVED (F15)**` — Pablo is genuinely unsure what is possible; must be invisible or escalate-to-author, never a raw conflict marker, never data loss (MTM-7). |

---

## Failure Points

*Where the system can fail, and the impact on experience. Ranked by severity. Each is a red-team finding with its designed containment.*

| # | Failure point (backstage) | Impact on user experience | Containment | Sev |
|---|----------------------------|----------------------------|-------------|-----|
| F1 | Managed profile missing a required key under `DisableWizard=true` | Silent mis-provision → false-Healthy over an empty department | Fail-closed schema validation → *IT-config-incomplete* + IT escalation (A-C1) | Crit |
| F2 | Vendored CLI binaries killed by Gatekeeper/quarantine | Every CLI spawn dies; the app can render only failures or misreads them | Cross-repo signed+notarized binaries; de-quarantine; `cli-spawnable` doctor check (A-C2) | Crit |
| F3 | Security-shadow relies on a notification Bob never sees | Vulnerable override keeps winning indefinitely | Auto-suspend the override + parallel IT escalation (A-C3) | Crit |
| F4 | Deprovision defeated by trashing the app / staying offline | A leaver's company content persists | MDM-native + server-side token revocation; honest offline boundary (A-C4) | Crit |
| F5 | Safety escalation gated behind off-by-default analytics | "IT notified" reaches no one; dashboard empty | Split safety from analytics; `AdminContact` on-by-default for managed (A-C5) | Crit |
| F6 | Two schedulers double-write `~/.copilot` | Torn `.claude/` tree; corrupt state on an ordinary machine | Single process + **CLI-side `flock`** (B-C1) | Crit |
| F7 | `KeepAlive=true` / rollback trapped in a crashing bundle | Menu bar crash-loops; Bob can't recover, no terminal | Crash-only watchdog + circuit breaker; watchdog-owned rollback + liveness heartbeat (B-C2/B-C3) | Crit |
| F8 | User-domain preference repoints update feed/mirror | Supply-chain RCE via a `defaults write` | Security keys honored only from the forced/managed domain (B-C5) | Crit |
| F9 | `--json` schema drift / missing field defaults to "safe" | Green shown over a red pipeline; a destructive repair read as safe | Bidirectional schema gate; missing security fields fail closed; "click to update" not "run doctor in a terminal" (B-H6) | Crit |
| F10 | Compat-matrix deadlock; no vendored-CLI owner | Red badge Bob can't clear, no admin rights | One owner; newer CLI *pulls* newer app; version-locked pair on `AllowSelfUpdate=false` fleets (B-C4) | Crit |
| F11 | Offline / seed-not-yet-published first-run | False-Healthy over foundation-only; whole fleet green-but-empty | *Waiting-for-network*; seed-vs-solo distinction via managed `EcosystemSeedURL` (A-H7/A-H12) | High |
| F12 | Quit mid-wizard, no daemon to finish | Machine sits half-provisioned, invisible to IT | Persist checkpoint + install watchdog at the first phase; resume headlessly (A-H6) | High |
| F13 | Held-major handed to Bob; used skill pruned silently; notif permission denied; login item toggled off | Bob-fatigue → he ignores the one alert that matters; silent degradation invisible to IT | Route by competence (central IT approval); notify on used-item prune; popover + IT fallback; managed login-item payload + disabled-state detection (A-H9/H10/H11/H13, B-H3) | High |
| F14 | Deprovision races a scheduled sync; profile-removal ambiguity; flap re-auth cost | Re-clone over a wipe; accidental wipe on re-scope; fleet-wide re-auth on a fat-finger | Global per-host mutex across all verbs; only explicit `Deprovisioned=true` wipes; debounce + soft-then-hard (A-M17, B-M1/M2) | Med |
| F15 | **Two authors edit the same department file → merge conflict; neither knows Git** | A raw `<<<<<<< HEAD` marker a non-technical person can't act on; a colleague's edits lost or the file stuck; a change-averse Bob concludes the tool broke his work — **trust make-or-break** (MTM-7) | Invisible/behind-the-scenes resolution where non-overlapping; plain-language "keep both / choose" for a true collision; **no data loss, no Git literacy**; escalate-to-author, never-lose if unsafe. **`> UNSOLVED · MODEL-IN-HEAD`** — deferrable *with* the multi-writer path, but must be solved before a 2nd writer gets access (`interview-ground-truth.md` §6) | **Crit** (when the write lane opens) |
| F16 | **Credentials-carrier in a pull-based model with no cloud secret store** | Push/pull auth can't reach a machine safely → the Write/Publish lane can't run, or secrets are carried insecurely | Designed secret-delivery (candidate: GitHub-as-carrier, mechanism TBD); **`> UNSOLVED`** — route to security/threat-model (`interview-ground-truth.md` §10) | **Crit** (blocks the lane) |
| F17 | **Personal content crosses into a shared/public tier** (the leakage wall) | Private personal information lands in an org/public repo — **irreversible**; Anxiety #2, the nightmare scenario; a change-averse Bob is gone for good | Structural personal/shared separation (distinct trees + remotes) + tier-scoped, **fail-closed** push = crossing is impossible by accident; **prevent-not-detect** (MTM-6) | **Crit** (new P0 guarantee, both consumers) |
| F18 | **Writable tier collides with never-destroy / read-only mirror** | A cadence pull carries a colleague's change over local author edits; a "read-only" mirror the author can write is no longer read-only → dirty-tree ambiguity | Trained-few-writers-first (blast-radius reduction, not removal); never touch a dirty personal tree; hold-and-escalate on ambiguity. **`> Flagged open architecture problem`** (invariant #3 tension) | High (design-open) |

---

## Blueprint Diagram

```
 STAGE        S1 DEPLOY (IT)      S2 PROVISION       S3 FIRST PARTNER   S4 STEADY-STATE    S5 CHANGE/HEAL     S6 ESCALATE        S7 DEPROVISION
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 CUSTOMER     author seed +       double-click /     read cheat sheet;  glance at icon     commit dirty WIP   re-affirm override old (IT) set
 ACTIONS      preflight + upload   approve 1 sign-in  add first skill    (Bob) / dashboard  *only when asked*  (rare) / IT approve Deprovisioned;
              MDM profile          confirm team (IT)                     (IT)                                  held-major          uninstall
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 FRONTSTAGE   Admin window:        silent bar OR      icon → solid;      icon + host-naming (usually nothing) Bob: "waiting on   "company content
 (visible)    generator →          ≤3-step wizard;    "teach" panel      status sentence;   rare, relevant     IT" (calm) /       removed" (honest
              red/green preflight  fail-closed card                      dropdown menu      notification       IT: actionable row  offline boundary)
 ═══════════════════════════ LINE OF VISIBILITY ═════════════════════════════════════════════════════════════════════════════════════════════
 BACKSTAGE    seed→PR; policy      doctor --bootstrap resolve/materialize freshness/doctor/ update --json →    auto-suspend +     Deprovisioned=true
 (CLI-owned)  SIGNED; profile+     schema-validate    (CLI); app PARSES  sync loops; status escalation router  parallel IT signal → soft-then-hard;
              payloads; PREFLIGHT  → IT-config-incompl only, never       computed CLI-side  (auto/IT/ask-Bob)  (content-free)      secrets_touched=0
              completeness         watchdog@phase-1                       parse-never-compute flock serializes                     server-side revoke
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 SUPPORT      Admin-mode gen;      MDM forced domain; SMAppService +     single-process     CLI-side FLOCK;    mandatory          MDM-native +
 PROCESSES    gh; capability-      cross-repo signed  launchd crash-only  supervisor; --json AdminContact      AdminContact       server-side token
              policy signer        CLI contract       watchdog            contract (WS-A)    safety channel     (on by default)     revocation; signed
                                                                                                                                    uninstaller
 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 FAILURE      F1 missing key       F1/F2/F11/F12      F2 Gatekeeper      F6 double-write    F3 shadow;         F5 no-op channel;  F4 un-wipeable;
 POINTS       (fail closed)        F8 pref repoint    F9 schema drift    F7 crash-loop      F13 Bob-fatigue    F13 held-major     F14 wipe race/flap
```

```
 AUTHOR LANE (Ada — runs alongside, MODEL-IN-HEAD)
 ─────────────────────────────────────────────────────────────────────────────────────────────
 W1 earn access   →  W2 author in Obsidian  →  W3 save & "publish"  →  W4 cadence → every machine  →  W5 collide/resolve
 (gated, grows)      (tier-scoped vault)        (button, not git)       (= Bob's Stage-4, other side)   (no Git · no data loss)
                              │                        │                          │                          │
                     leakage wall (F17)         fail-closed push          author "landed on N"        merge-conflict (F15)
                     personal↔shared            tier-correct only         confirmation                 writable-tier vs #3 (F18)
                                                credentials-carrier (F16, UNSOLVED)
```

**How to read it:** the frontstage is deliberately thin — a bar, an icon, a sentence, a rare
notification, and (for the author) a publish button that is never a Git terminal. Everything
load-bearing lives *below* the line of visibility, in the CLI + `flock` + watchdog + MDM/minisign
trust chain — and now the **write/publish path** (Obsidian → push → cadence sync). That asymmetry
**is** the product: Control Tower is trustworthy precisely because it computes nothing and its whole
substance is a hardened backstage it merely renders. Every failure point above is a backstage failure
with a designed containment — because for this product, the backstage is where trust is won or lost.
The **new author lane (F15–F18)** is the least-settled part of that backstage: two of its four
failure points are stamped **UNSOLVED**, and the whole lane is **MODEL-IN-HEAD** — never run with more
than one writer.

---

**Related:** [Journey Maps](20-journey-maps.md) | [Moments That Matter](40-moments-that-matter.md) | [JTBD](30-jtbd.md) | [CLI Contract](../../01-architecture/cli-contract.md)
