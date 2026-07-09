> **Superseded framing.** This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of "product" to mean a CSE tool are superseded. The corrected model is in `docs/reference/copilot-solutioning-ecosystem.md`; the decisions are in `docs/reference/cse-alignment-decisions.md`.

# User Journeys

> **Provenance.** Grounded synthesis from `00-vision.md`, `30-jtbd.md`, `01-interview-self.md`, and
> the engineering source (`architecture.md` §2–§9, `redteam-use-cases.md` [A], `redteam-platform.md`
> [B], `ecosystem-use-cases.md`). Struggling moments are drawn directly from the red-team failure
> scenarios — those *are* the moments where trust is won or lost. Emotions are specific and
> contextual, never "frustrated / happy." Genuine unknowns marked `<!-- TODO -->`.

---

## Personas

- **Bob (primary — change-averse consumer)** — non-technical employee, no terminal, denies OS prompts,
  ignores single nudges, may run Focus/DND. **A psychology, not a role** (any department can *be* Bob):
  values control, fears being *wrong* (the fear is professional consequence — lose information, lose the
  company money, lose the job), and is **intensely detail-oriented** — which means he *will catch* a
  dishonest status. Arrives *braced for friction* because "IT software" has taught him to expect it.
  Wants to feel **SAFE**; the target emotion is **comfortable AND excited** — "superpowers he's wanted
  his entire career and is only now getting."
  > **Evidence: GROUNDED** (Bob's psychology — real people across real companies) / **HYPOTHESIS** (the
  > *full* ecosystem actually reaching a non-technical person unaided — never run end-to-end; Claude
  > Copilot is TESTED with a real team, but the Knowledge/CLI-Copilot-to-Bob path is the un-run bet).
- **Ada (NEW — trained early-adopter author)** — sits *between* Pablo (foundation) and Bob (consumer): a
  trained innovator with **earned, gated** write access to org / department content, authoring in a
  markdown editor (**Obsidian**) → save → push → sync. More comfortable than Bob; wants **POWER**. Not a
  Git user.
  > **Evidence: MODEL-IN-HEAD** — the multi-writer authoring loop (Obsidian → save → push → sync) has
  > **never been run with more than one writer.** This entire journey is a model, not an observation.
- **Earl (IT / Admin, primary Admin-mode)** — platform lead standing up + deploying the ecosystem;
  owns the fleet; arrives *wary of a token-holding always-on agent* his security team will question.
  > **Evidence: HYPOTHESIS** — no real IT operator has stood up the ecosystem, watched a fleet
  > dashboard, or run a deprovision. This entire journey is an untested behavioral bet.
- **Pablo (ecosystem owner)** — authors the foundation (the *foundation-tier case of Ada's job*); today
  the *only* operator, keeping two machines in parity **by hand**; arrives *anxious that the always-on
  face makes the ecosystem riskier to adopt*, and needs the opposite to be provably true.
  > **Evidence: OBSERVED** (his daily hand-sync pain).
- **Rosa / Dwayne (secondary context)** — developers on the CLI; their journey is "nothing changed for me
  and my tree wasn't touched." Abbreviated below as a do-no-harm check.

**Primary persona we design for first: Bob** (change-averse consumer). Ada (author) is the new
second-priority persona; Bob-first primacy holds.

---

## 1. Bob — Non-Technical Employee (Primary) Journey

```
Handoff → Silent/≤3-Q Provision → First Partner (aha) → Invisible Steady-State → The Honest Interruption → A Trust Test → Clean Exit
```

**Stage 1: Handoff — the laptop arrives**
- Bob receives a work Mac (managed by IT) or is told to "double-click the Control Tower icon." He
  knows nothing about layers, YAML, or `copilot`.
- Emotional state: **braced** — "I am expecting this to be another IT thing that makes me call the
  help desk."
- Pain (today): onboarding *is* a shell script + a department prompt he has no basis to answer
  (`ecosystem-use-cases.md` UC1). He can't start.
- Solve: on a managed fleet IT already pushed the app + `.mobileconfig`; Bob does nothing, or at most
  double-clicks once. No terminal appears.

**Stage 2: Provision — the wizard runs (silently, or asks ≤3 things)**
- On a managed machine the wizard runs **silently** (Bob watches a progress bar, is asked nothing);
  unmanaged, he's asked *at most three* things — host only if ambiguous, one sign-in approve, and
  company/team (`architecture.md` §4). Everything else is derived.
- Emotional state: **watchful, then surprised-it's-easy** — "I am waiting for the part where it asks
  me something I can't answer... and it doesn't."
- Pain (today): the shell script asks him to confirm a department and read `copilot update` output he
  can't judge; a missing MDM key would silently mis-provision him (A-C1).
- Solve: the wizard installs the login-item + crash-watchdog at the **first** phase (so a quit
  mid-setup resumes headlessly — fixes A-H6); it schema-validates the managed profile and **fails
  closed** into a visible *IT-config-incomplete* state rather than guessing (A-C1); offline, it
  finishes foundation-only and enters *Waiting-for-network* instead of false-Healthy (A-H7).

**Stage 3: First Partner — the aha (superpowers, not just setup)**
- The wizard ends on a short "teach" step (cheat-sheet + "add your first skill" + offer backup). Bob
  has a working, company-scoped Copilot partner in Claude and/or Codex. He never saw a terminal. The
  teach step deliberately shows a *solution-oriented* first ask ("help me build the report I never get,"
  not "answer a trivia question") to seed the habit-break from day one.
- Emotional state: **relieved → quietly excited** — "I am set up, I didn't have to be technical, and
  this can do things the chat app never could." This is the *comfortable AND excited* target: the
  superpowers he's wanted his whole career, only now arriving.
- Pain (today): there is no non-technical path to this state at all; without it he stays stuck in the
  software IT handed him.
- Solve: this *is* the Magic Moment (`00-vision.md`) — the delivery of the democratization job B0 via
  its entry gate B1.

**Stage 3b: Reaching for it — breaking the generic-chat habit** *(the recurring adoption transition)*
- Over the following weeks, every time Bob has a question — "what email do I send this person," "help
  me shape this strategy," "I'm not getting the report I need, let's build one" — he faces a fork:
  reflexively open the Claude app / ChatGPT / Gemini, or reach for the solution-oriented partner.
- Emotional state: **tempted by the familiar** — "I am about to default to the chat app I've always
  used, because it's right there and I know it."
- Pain (today): the generic chat tool *only answers*; it doesn't build, integrate, persist, or know his
  company — but it's the path of least resistance, and the habit wins.
- Solve: the partner must be *more present and more capable at the moment of need* than the generic app
  — so the reflex shifts from "ask a chatbot" to "have my partner build it." **This transition is where
  adoption is actually won or lost** — B1 delivers the tool; B6 decides whether he *uses* it.
  <!-- TODO: what is the concrete surface that intercepts the habit at the moment of need? A launcher,
       a hotkey, a menu-bar entry point? Undesigned — route to interaction design (@agent-uxd). -->

**Stage 4: Invisible Steady-State — it stays working on its own**
- For days/weeks the menu-bar icon just sits there, solid. The supervisor polls (freshness ~15m,
  doctor ~1h, sync ~6h while running), self-heals reversible drift, and defers non-security updates
  while a host session is live (A-H8). An authorized change made once upstream simply *appears* on his
  machine on the next cadence, without his attention and without touching his personal work. Bob is not
  interrupted.
- Emotional state: **oblivious, in the good way** — "I am not thinking about it, which means it's
  doing its job." His environment stays *Copilot-ready* on its own.
- Pain (today): manual `copilot update` swallows prunes + security trailers into cron; the machine
  drifts silently; nobody can see it (`architecture.md` §8.3, §9).
- Solve: always-on self-heal + honest glanceable status that **names the failing host** in plain
  language ("Codex needs sign-in; Claude is fine") — never a blended verdict (A-M14). Because Bob's
  detail-orientation *will catch* a false green, the icon that cannot lie is the survival condition of
  this whole stage.

**Stage 5: The Honest Interruption — asked only about his own data**
- Rarely, the system needs *Bob specifically*: "commit your dirty personal work before I sync," or the
  one sign-in re-approve. A skill he actually *used* was pruned by an update → he's told ("a tool you
  used was removed"), not left to discover it (A-H9).
- Emotional state: **trusting, because it's rare and relevant** — "I am being asked about *my* stuff,
  which is the only time it ever bugs me — so I pay attention."
- Pain (today): the old model notified Bob about everything (policy denials, held-majors) he couldn't
  act on, training him to ignore it (A-M15, C3).
- Solve: route by *actor-competence × reversibility* — auto-act on reversible things he can't judge,
  escalate to IT what he can't action, ask him *only* about his own data (invariant #5).

**Stage 6: A Trust Test — something goes wrong (the moment loyalty is decided)**
- A security fix ships that a personal override was shadowing; **it is auto-suspended** so the fixed
  version wins immediately (reversible — Bob can re-affirm) and IT is escalated in parallel (A-C3). Or
  a held-major awaits — Bob sees a non-actionable "waiting on IT," never a decision he can't make
  (A-H11). Or a bad self-update is discarded by the watchdog before he ever sees a crash (B-C3).
- Emotional state: **reassured rather than alarmed** — "I am seeing that when something *was* wrong,
  it either fixed itself or went to the right person — not dumped on me."
- Pain (today): the vulnerable override keeps winning behind a notification he never opens; a
  held-major decision lands on the least-competent actor; a bad update crash-loops the menu bar.
- Solve: auto-act + escalate on the security shadow; central IT approval for held-majors;
  watchdog-owned rollback gated on an early liveness heartbeat.

**Stage 7: Clean Exit — removal or offboarding**
- Bob leaves, or uninstalls. Deprovision is MDM-native + server-side token revocation — even if he
  trashes the app or stays offline, company content can't quietly persist and the next online
  `update` fails closed and wipes (A-C4). A signed uninstaller avoids orphaning the login item /
  watchdog (B-H2).
- Emotional state (Bob) / **relief (IT)** — "I am gone and nothing company-owned is lingering on my
  machine; IT can prove it."
- Pain (today): deprovision is contingent on a user-deletable app choosing to run it.
- Solve: the honest boundary is stated plainly — an offline machine can't be *remotely wiped*; the
  guarantee is "no secret ever materialized," not "exfiltration undone" (`architecture.md` §8.3).

---

## 2. Ada — Trained Early-Adopter Author Journey (NEW writable tier)

> **Evidence: MODEL-IN-HEAD** — the multi-writer authoring loop (Obsidian → save → push → sync) has
> **never been run with more than one writer.** Every stage below is a *model*, not an observation; the
> two hardest moments (leakage wall, merge-conflict) are **UNSOLVED.** Ada wants **POWER**, not just
> safety — but she is *not* a Git user, and the personal↔shared boundary must protect her too.

```
Earn access → Author in Obsidian → Save & Publish → It Lands Everywhere → The Collision → The Boundary Holds
```

**Stage 1: Earn access — from consumer to author**
- Ada, a trusted early-adopter in Finance, is granted **gated, earned** write access to her
  department's repo (write access *starts* with a few innovators and grows as demand rises).
- Emotional state: **trusted, a little proud** — "I am being handed the keys the technical people had;
  I get to extend this, not just use it."
- Pain (today): there is no tier between "read-only consumer" and "Pablo who owns a terminal"; a
  non-technical contributor simply cannot contribute.
- Solve: an earned, gated write grant + a tier-scoped Obsidian vault — power without a release process.

**Stage 2: Author — writing in a familiar editor**
- She opens her Obsidian vault and edits a department Knowledge Copilot doc (or a skill/agent/CLI
  integration) — loading files and writing, or having AI update the docs. The vault makes clear
  *which tier* she is editing.
- Emotional state: **capable, in flow** — "I am writing in a tool I already understand; I never see a
  terminal or a YAML file."
- Pain (today): the only authoring path is the CLI + Git, which she can't use.
- Solve: Obsidian as the authoring surface; personal and shared content live in **separate trees** so
  a personal note can't wander into a department file.

**Stage 3: Save & Publish — one button, never a `git push`**
- She saves and clicks "publish." A plain-language "publishing your change to *Finance*…" → "published"
  confirms it. She never typed a Git command.
- Emotional state: **decisive, slightly braced** — "I am pushing a change other people will depend on;
  I want to know it went to the *right* place and only the right place."
- Pain (today): publishing means `git commit`/`git push` and knowing which remote — a technical act.
- Solve: a publish button that runs the tier-correct push, **fails closed** if the change touches a
  tier she can't write, and can never select personal content (the leakage wall, enforced here).

**Stage 4: It Lands Everywhere — the everyday-hero payoff (W1)**
- She does nothing more. On the next cadence (~6h), every machine in Finance pulls her change quietly,
  without touching anyone's personal work; she gets a "landed on N machines" confirmation.
- Emotional state: **released** — "I made the change **once** and I never have to wonder whether it
  landed. The system carried it." This is the author-side of Pablo's *"keeps your environment
  Copilot-ready."*
- Pain (today): Pablo hand-carries every change between machines; nothing propagates unless he
  remembers — "that shit gets exhausting."
- Solve: cadence-based pull on every consumer machine; a manual "sync now" as an escape hatch;
  per-minute refresh is explicitly *wrong*.

**Stage 5: The Collision — a colleague edited the same file** *(the merge-conflict moment; UNSOLVED)*
- Bob (also in Finance) edited the same financial file; the syncs collide. **Neither knows Git.**
- Emotional state: **alarmed → about-to-abandon** — "I am terrified I lost my colleague's work, or he
  lost mine, and I have no idea what this message means." For a detail-oriented, change-averse person,
  *the tool broke my work* is the worst possible feeling.
- Pain (today): a raw `git merge` conflict marker neither can act on; edits lost or stuck.
- Solve *(hypothesized)*: resolve invisibly where non-overlapping; a plain-language "keep both /
  choose" for a true collision; **no data loss, no Git literacy**; escalate to a competent author if it
  can't be made safe — **never** show a conflict marker, never lose a byte (MTM-7).
  <!-- TODO: what is technically possible for invisible, non-technical resolution? Pablo is genuinely
       unsure. Route to architecture/security — this gates opening write access to a 2nd author. -->

**Stage 6: The Boundary Holds — personal never crosses into shared** *(the leakage-wall moment)*
- At some point Ada (or Bob) has a personal writing-style note near department content and a sync is
  about to run. One careless push *could* carry private personal information into a shared/public repo.
- Emotional state: **quietly protected** — "I am not even given the chance to make that mistake; the
  system won't let personal cross into shared." The nightmare (Anxiety #2) never gets a chance to happen.
- Pain (today): the wall is entirely in the user's head — "just don't push personal stuff"; one
  fat-finger is an irreversible leak.
- Solve: structural personal/shared separation + tier-scoped, fail-closed push = crossing the boundary
  is **impossible by accident** — prevent, don't detect (MTM-6; F17).

---

## 3. Earl — IT / Admin Operator Journey (abbreviated)

```
Evaluate trust → Author seed → Generate MDM profile → Preflight → Deploy → Watch fleet → Govern & Offboard
```

- **Evaluate trust:** needs to know a token-holding always-on agent is auditable → reads the
  security-&-trust doc; open source + reproducible builds + two-of-N signing (`architecture.md` §7–§8.2).
- **Author seed:** guided seed generator writes `ecosystem.yml` + opens the PR — no hand-YAML (A1).
- **Generate MDM profile:** one `.mobileconfig` (managed keys + login-item + notifications payloads)
  so every wizard runs silent (`architecture.md` §8.1).
- **Preflight:** red/green report *before* pushing — seed parses, dept repos exist, policy signed,
  profile complete for the silent path, foundation pin resolves, mirror reachable.
- **Deploy:** upload one artifact to Jamf/Kandji/Intune; the fleet self-provisions.
- **Watch fleet:** dashboard — healthy / stuck / behind / needs-auth at a glance (A2; the named gap).
- **Govern & Offboard:** held-majors + policy conflicts route to him centrally (A3); explicit
  `Deprovisioned=true` triggers soft-then-hard wipe (A4).

## 4. Pablo — Ecosystem Owner Journey (abbreviated)

```
Ship a security fix → Trust it propagates → Audit → Pass an enterprise review
```

- **Ship a fix:** publishes a `security:`-trailered change to the foundation.
- **Trust it propagates:** the vulnerable shadowing override is auto-suspended fleet-wide, not left to
  a notification (O1); an "urgent-since" marker can override battery/metered backoff (A-M16).
- **Audit:** content-free, hash-chained action log anchored to the org endpoint (A5, L2).
- **Pass a review:** the always-on agent is demonstrably *safer than manual* — zero bypass flags,
  every pull visible/verified/policy-bounded/auditable; parse-never-compute holds (O2/O3).

## 5. Rosa / Dwayne — Developer (do-no-harm check)

```
Keep using the CLI → Tree untouched → No double-write
```

- Runs `copilot update` / `resolve --explain` by hand as always; Control Tower's CLI-side `flock`
  means no process arrangement double-writes (`architecture.md` §3); a dirty personal tree is never
  touched (invariant #3). **Success = they don't notice Control Tower at all.**

---

## Struggling Moments

*The priority design targets — every row is a red-team failure where trust is lost.*

| Moment | What Goes Wrong | What They Need | Severity |
|--------|-----------------|----------------|----------|
| Silent wizard, missing MDM key | `DisableWizard=true` strips the ability to ask; a missing `Department`/`OrgSlug`/`EcosystemSeedURL` → hang or false-Healthy on an empty department (A-C1) | Fail **closed** into a distinct *IT-config-incomplete* state + IT escalation; never guess, never Healthy | **Critical** |
| Gatekeeper kills the vendored CLI spawn | Vendored `copilot`/`cc` outside the signed bundle carry quarantine → every spawn dies; app renders only failures or misreads them (A-C2) | Cross-repo signed+notarized binaries, de-quarantine, a `cli-spawnable` doctor check as a *named* finding | **Critical** |
| The security shadow Bob never sees | Override still wins; the only signal is a notification inside a dropdown Bob never opens, under Focus/DND (A-C3) | **Auto-suspend** the override (reversible) + escalate to IT — never notify-and-hope | **Critical** |
| The un-wipeable leaver | Bob trashes the app / stays offline → the MDM signal has no local actor; company content persists (A-C4) | MDM-native deprovision + server-side token revocation; honest "no secret materialized" boundary | **Critical** |
| Offline first-run | New laptop on home wifi; wizard finishes foundation-only and (falsely) shows Healthy or a scary error (A-H7) | A distinct *Waiting-for-network* holding state; supervisor completes company clones on reconnect | **High** |
| Quit mid-wizard | Bob quits after clone but before materialize; no daemon to finish; next launch restarts from zero (A-H6) | Persist checkpoint + install watchdog at the **first** phase; resume headlessly | **High** |
| Held-major dumped on Bob | "Review and approve — or wait for IT" hands a major-bump decision to someone with no basis to judge (A-H11) | Route to IT centrally; Bob sees a non-actionable "waiting on IT" | **High** |
| A used skill silently pruned | A daily-used tool vanishes; surfaced only in a menu Bob never clicks (A-H9) | Notify on a prune of a *recently-used* item ("a tool you used was removed"); zero-usage prunes stay silent | **High** |
| Notification permission denied | Bob denies the macOS prompt → the whole notify tier is dead with no fallback (A-H10) | Detect denied state; fall back to popover for high-severity + re-route safety events to the IT channel | **High** |
| Login item toggled off | Bob (or a naive act) disables the SMAppService login item → background sync silently dies, indistinguishable from a powered-off Mac (B-H3) | Managed login-item MDM payload (non-toggleable) + detect `.requiresApproval` + emit "persistence disabled" to IT | **High** |
| Bad self-update crash-loops the menu bar | A bundle that crashes on launch traps its own rollback; under `KeepAlive=true` it storms (B-C2/B-C3) | Watchdog-owned rollback gated on an early liveness heartbeat; `KeepAlive={SuccessfulExit:false}` + circuit breaker | **Critical (platform)** |
| Schema drift shows green over red | A misread `fail`→`pass`, or a missing security field defaulting to "safe" (B-H6) | Bidirectional `min/max_schema` gate; **missing security fields fail closed**; "click to update" in-app, never "run doctor in a terminal" | **Critical (platform)** |
| **The leakage wall** (personal → shared) | A personal writing-style note is about to be carried into a department/org repo by a sync or a careless publish; private personal info could land in a shared/public place — **irreversible** (Anxiety #2) | Structural personal/shared separation (distinct trees + remotes) + tier-scoped, **fail-closed** push = crossing is **impossible by accident**; prevent-not-detect (MTM-6 · F17) | **Critical (new P0 · both consumers)** |
| **The merge-conflict** (two authors, one file, no Git) | Bob + a colleague edit the same department financial file; syncs collide → a raw `<<<<<<< HEAD` marker **neither can act on**; edits lost or stuck; a change-averse Bob concludes the tool broke his work | Invisible resolution where non-overlapping; plain-language "keep both / choose"; **no data loss, no Git literacy**; escalate-to-author if unsafe (MTM-7 · F15). **`> UNSOLVED · MODEL-IN-HEAD`** | **Critical (when the write lane opens)** |

---

## Emotional Arc (Bob)

| Stage | Feeling | What Builds Confidence | What Could Go Wrong (emotionally) |
|-------|---------|------------------------|-----------------------------------|
| Handoff | **Braced** — expecting friction | Zero questions on a managed fleet; one double-click | A terminal or a config prompt appears → "this is going to be a support ticket" |
| Provision | **Watchful → surprised-it's-easy** | Progress bar; nothing asked he can't answer | A silent hang, or a false-Healthy over an empty department → invisible mis-provision |
| First Partner | **Relieved, quietly impressed** | A working partner + a plain-language cheat sheet | An error he can't parse → "I'm broken and I don't know why" |
| Steady-State | **Oblivious (good)** | The icon stays solid; he's never bugged | A silent drift he can't see, or a nag he can't act on |
| Honest Interruption | **Trusting** (it's rare + relevant) | Only ever asked about his own data | Being asked to judge a held-major or a policy → learned helplessness, then ignore-everything |
| Trust Test | **Reassured, not alarmed** | The fix acted itself; the decision went to IT | The vulnerable version keeps winning; a crash-loop; a decision dumped on him |
| Clean Exit | **Clean / (IT: relief)** | Nothing company-owned lingers; provable | An orphaned login item; content persisting; a false "wiped" claim |

**Two psychographics, two arcs.** Bob's arc (above) bends toward **safety** — braced → oblivious →
reassured; every peak is a *relief*, every risk is a *breach of trust*. Ada's arc (below) bends toward
**power** — trusted → in-flow → released; her peaks are *capability*, and her two risks (the collision,
the boundary) are exactly where power turns back into fear. The design must serve both without
collapsing them.

## Emotional Arc (Ada — the author) `> **Evidence: MODEL-IN-HEAD**`

| Stage | Feeling | What Builds Confidence | What Could Go Wrong (emotionally) |
|-------|---------|------------------------|-----------------------------------|
| Earn access | **Trusted, a little proud** | The keys the technical people had, handed to her | A gate that feels arbitrary or ungoverned |
| Author in Obsidian | **Capable, in flow** | A familiar editor; no terminal, no YAML | Ambiguity about *which tier* she's editing |
| Save & Publish | **Decisive, slightly braced** | "Published to *Finance*" — the right place, only the right place | A `git push` she doesn't understand; a push to the wrong tier |
| It Lands Everywhere | **Released** | "Landed on N machines" — made once, never wondered | Silent non-propagation; having to babysit the sync |
| The Collision | **Alarmed → about-to-abandon** | *(hypothesized)* invisible resolve; "keep both / choose"; no data loss | A raw Git conflict marker; a colleague's work lost — *the tool broke my work* |
| The Boundary Holds | **Quietly protected** | The system won't *let* personal cross into shared | Private personal info in a shared repo — irreversible; gone for good |

---

## Touchpoints

*Ranked by impact on Bob's experience.*

1. **The menu-bar icon + one-line status sentence** — the highest-impact touchpoint; it's the honest
   projection of `doctor --json`, worst-wins across hosts, naming the failing host (`architecture.md`
   §2). If this lies, everything else is worthless.
2. **The first-run wizard** (silent progress bar or ≤3 questions) — decides the Magic Moment.
3. **The dropdown menu** (Sync now, Repair, What changed, Add a skill, Sign in, Hosts ▸, Preferences,
   Quit) — each action spawns a CLI verb; the menu never mutates state.
4. **Notifications** — rare by design; fire only when Bob is the sole competent actor (invariant #5).
5. **The Admin-mode window / fleet dashboard** (Earl) — the observability surface + generators.
6. **The Obsidian authoring surface + "publish" action** (Ada) — the write-lane touchpoint; a
   tier-scoped vault + a publish button that is *never* a Git terminal, with the leakage wall enforced
   at the point of push. `> **MODEL-IN-HEAD**`.
7. **Outside-the-product:** the MDM push (Jamf/Kandji/Intune), the IT `AdminContact` safety channel,
   the browser device-flow sign-in.

---

## Intelligence Handoffs (Ecosystem)

| Handoff | From → To | What Flows | What Breaks If It Fails |
|---------|-----------|------------|--------------------------|
| Health verdict | CLI `doctor --json` → Control Tower | `{score, status, checkers, auth}` — **status computed CLI-side** | The icon has nothing honest to render; parse-never-compute means the app *cannot* fake it (fails closed) |
| Change set | CLI `update --json` → Control Tower | `changed[]` (op/layer/item/signed/`severity_trailer`/`shadowed_by`), `held_for_approval`, `blocked` | The what-changed panel + security-shadow auto-suspend lose their trigger |
| Poll target | CLI `freshness --json` → supervisor | single `latest_lock_sha` vs `current` | Drift detection stops; the machine silently falls behind |
| Org config | MDM managed profile → Control Tower | forced-domain security keys + login-item + notifications payloads | Silent path can't run; missing key → fail-closed *IT-config-incomplete* |
| Seed | `ecosystem.yml` → CLI `derive` | products, dept, pins, policy signers | Wizard 404s; must distinguish "seed coming" from "solo" (A-H12) |
| Fleet telemetry | Control Tower → IT dashboard | org-scoped, PII-minimized `{org,dept,foundation}` items + health, keyed by per-user salted `machine_id` | Observability gap reopens; a personal name must be *un-emittable by construction* (B-H5) |
| Safety escalation | Control Tower → IT `AdminContact` | content-free signals (sig-fail, auth-revoked, policy-conflict, stalled-onboarding, persistence-disabled, notifications-off) | "IT notified" becomes a no-op — the C5 failure class |
| Deprovision | MDM `Deprovisioned=true` → CLI `deprovision --json` | `removed{}`, `retained_dirty[]`, `secrets_touched==0` | A leaver's content persists (A-C4) |
| Author publish | Obsidian save → CLI `publish --json` (or equiv) → tier-correct remote | tier-scoped commit + push; personal content **un-selectable**; fail-closed on wrong tier | Personal content leaks into a shared repo (F17); a push to the wrong tier. `> **MODEL-IN-HEAD / UNSOLVED**` |
| Cadence propagation | Author push → every consumer's `freshness`→`update` pull (~6h) | the author's change carried to every machine, deferring while a host session is live | The everyday-hero mechanism dies; the author becomes the sync layer again |
| Merge-conflict | Two authors → colliding pushes on one file | *(hypothesized)* invisible resolve or "keep both / choose"; **no data loss** | A raw Git conflict marker; a colleague's edits lost (F15). `> **UNSOLVED**` |

---

## Critical Design Requirements (Summary)

| Requirement | Why | Success Metric |
|-------------|-----|----------------|
| Honest, never-false-Healthy status that names the failing host | False-Healthy is the worst outcome; it makes the icon a liar (`20-success-metrics.md`) | Zero false-Healthy in the field; *Waiting-for-network* / *IT-config-incomplete* used correctly |
| Silent managed provision with fail-closed validation | Bob can't answer questions; a missing key must not mis-provision | Managed machines reach a *true* terminal state (~0% false-Healthy) |
| Route by actor-competence × reversibility | Every alert Bob can't act on burns the one that matters | Bob-facing notification count trends toward zero; escalations land on the right actor |
| Auto-suspend security-shadowing overrides | A security fix must never depend on a notification Bob never sees | 100% coverage — any miss is a Critical regression |
| Single process + CLI-side `flock`; crash-only watchdog | Two schedulers tore `.claude/`; `KeepAlive=true` crash-loops | Exactly one binary; no torn tree under concurrent invocation |
| Security keys honored only from the forced/managed domain | User-domain override → supply-chain RCE | No user-domain security key ever honored; tamper events logged |
| Never touch a dirty personal tree | Trust + the do-no-harm guarantee for Rosa/Dwayne | Zero incidents of Control Tower mutating a dirty working tree |
| MDM-native, offline-honest deprovision | A user-deletable app must not be the sole wipe trigger | Access revoked on next online update even if the app is trashed |
| Structural personal↔shared separation (the leakage wall) | Personal content in a shared/public repo is irreversible — Anxiety #2; prevent, don't detect | Zero personal-layer artifacts reachable by a shared remote; a cross-tier push fails closed (new P0) |
| Non-technical merge-conflict resolution *(UNSOLVED)* | Two non-Git authors must never lose work or see a conflict marker | No data loss; no Git literacy required; escalate-to-author if unsafe. `> **MODEL-IN-HEAD**` — solve before opening write access to a 2nd author |

---

## Service Blueprint Layers

| Layer | Description |
|-------|-------------|
| **Customer Actions** | Double-click (or nothing, managed); approve one sign-in; commit dirty WIP when asked; glance at the icon. **Author (Ada):** author in a tier-scoped Obsidian vault → save → "publish." IT: author seed, generate + preflight + upload MDM profile, watch dashboard, approve held-majors, set `Deprovisioned`. |
| **Frontstage** | Menu-bar icon + one-line status sentence; first-run wizard (silent/≤3-Q); dropdown menu; rare notifications; **the Obsidian authoring surface + a "publish" button (never a Git terminal) + plain-language conflict resolution**; Admin-mode window + fleet dashboard + red/green preflight. |
| **Backstage** | The `copilot`/`cc` CLI verbs (`doctor`/`update`/`repair`/`resolve`/`deprovision`/`freshness --json`); `flock` self-serialization on `copilot.lock`; single-process supervisor + timer loops; the actor-competence escalation router; `launchd` crash-only watchdog + liveness-heartbeat rollback. **Write/publish path:** tier-scoped commit + push to org/dept remotes; cadence-based pull to every machine; non-technical merge-conflict resolution *(UNSOLVED)*. |
| **Support Processes** | MDM forced-domain config (`dev.enac.controltower`); minisign + two-of-N signing trust chain + notarization/staple; cross-repo signed-CLI artifact contract; server-side token revocation; opt-in org-scoped telemetry sink; mandatory `AdminContact` safety channel. **Writable org/dept remotes + gated push authority** *(MODEL-IN-HEAD; strains never-destroy)*; **personal↔shared tier separation** (leakage wall); **credentials-carrier** *(UNSOLVED)*. |

---

**Related:** [JTBD](30-jtbd.md) | [Moments That Matter](40-moments-that-matter.md) | [Service Blueprint](10-service-blueprint.md)
