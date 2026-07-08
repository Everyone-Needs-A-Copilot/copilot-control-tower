# Copy & Voice

> **Provenance.** Grounded translation, not fresh invention. Every string below is the copy for a
> state, flow, or moment already designed in `50-ux-design.md` (the status-icon state matrix, the two
> wizard paths, the notification pattern), a trust-defining moment in `02-service-design/40-moments-that-matter.md`,
> or an error/edge scenario (`03-requirements/20-use-cases-and-scenarios.md`, E1–E22). The voice is
> lifted verbatim in intent from `SOUL.md` §7 (Voice & Tone) and its anti-pattern **"The Alert Machine"**.
> Genuine unknowns are marked `<!-- TODO -->`.
>
> **This document is the source of truth for every word in the product.** Design and implementation
> copy strings **from here** — no paraphrasing, no improvising a friendlier tone at build time. When a
> string is missing, add it here first.

---

## Two registers, one voice

The **same event** surfaces to two very different people. The voice (the air-traffic-controller
character) is constant; the register modulates.

| Register | Who | Rule |
|---|---|---|
| **Bob-facing** | The non-technical primary persona. No terminal, denies permission prompts, may run Focus/DND. | Plain language. **Zero jargon.** Names the failing **product and layer** and the one thing to do. Reassuring only as far as the CLI can prove it. |
| **IT/Admin-facing** | Earl and the org security team, in the Admin window. Competent, technical. | Precise and technical-OK: key names, host names, finding IDs, counts, SHAs. Still calm, still never alarmist. |

Where a string below shows both, the event reaches both surfaces at once (e.g. IT-config-incomplete,
the security auto-suspend, a persistence-disabled Mac). **A word that is fine for Earl is not
automatically fine for Bob** — Bob never learns "profile", "schema", "key `EcosystemSeedURL`",
"exit code", "CLI", "flock", "YAML", or "daemon". See **Banned Language**.

---

## Voice

### Character

**An air-traffic controller.** Calm, spare, never theatrical. It watches every flight, keeps them
coordinated, clears them to proceed, and raises the alarm when something is genuinely off. It says
exactly what is true and no more. It never flies the plane, never guesses, and never pretends the
weather is clear when it can't see the sky. **When it has nothing to say, it says nothing — and that
silence is the signal that everything is fine.** (`SOUL.md` §2, §7.)

The single promise every string must keep: **the icon that cannot lie.** Copy is

- **Honest** — it never says "All good" when it can't prove it. Offline, mid-setup, or unreadable
  reads as an *honest holding state*, never a fabricated "fine".
- **Calm** — no alarm words, no fake urgency, no red-alert theatre, even at a real failure. Failure
  copy is a plain sentence and a next step, not a siren. (Anti-pattern: *The Alert Machine*.)
- **Plain for Bob** — a glance answers "is it OK, and do I have to do anything?" in one sentence a
  non-technical person reads in half a second.

### Speech Patterns

| Rule | Do | Don't |
|---|---|---|
| **Short.** One idea per sentence; a status line is one sentence. | "CLI Copilot — department layer needs sign-in." | "There are one or more issues that may require your attention across your configured products." |
| **Name the specific thing — product AND layer.** Never a blended verdict, never just a product. | "Claude Copilot — org layer updating…" | "Something needs your attention." |
| **Second person, present or past — never future-promise what isn't done.** | "I'll finish setup when you're back online." | "Your setup is complete!" (when it isn't) |
| **The system speaks in the language of supervision** — watch, hold, sync, sign in, waiting on — never *decide, know, resolve, score*. | "An update is waiting on IT." | "The AI decided to defer this update." |
| **Past-tense for anything already handled.** Auto-acted things are reported, not asked. | "Kept you safe — a security fix replaced a component you'd overridden." | "A security issue needs your approval." |
| **No numbers Bob can't use.** No error codes, no SHAs, no key names in his register. | "Versions don't match." | "Schema out of range (min 4, got 6); exit 2." |
| **Understate success.** Silence beats a toast; a toast beats a celebration. | *(nothing)* / "Up to date." | "🎉 All done! You're all set! Great job!" |

### Voice Role

Control Tower is a **supervisor that reports to you**, not an assistant that performs for you and not
a friend that cheers you on. To **Bob**, it is the quiet colleague who only ever speaks up about *his*
things and handles the rest without a fuss — and who, crucially, tells him the truth even when the
truth is "not yet." To **Earl**, it is a precise operations console: dense, factual, deep-linkable, and
equally incapable of showing green over red.

It is never the pilot. It renders the CLI's verdict in plain language; it never generates a verdict of
its own. Every string is a *parse*, not an opinion.

---

## Key UI Copy

### A. The status dropdown — every state (the product's most load-bearing copy)

Each row is the exact copy for a state in the state matrix (`50-ux-design.md` → Status-Icon State
Matrix). **Top line** is what Bob reads first. **Primary action** is the one button. **IT-facing** is
what the same event says on the Admin surface (blank = Bob-only or no separate IT string). No status
line ever claims more than the CLI proved.

| State (family) | Bob top line | Primary action label | Secondary / note | IT/Admin-facing line |
|---|---|---|---|---|
| **Healthy** (Healthy) | *(no notification; dropdown top line if opened:)* "Everything's in sync across all your copilots." | "Sync now" (optional) | "What changed" · "Add a skill" · "Open cheat-sheet" | "Healthy — every product on the current version across all 4 layers, signed in." |
| **Syncing** (Working) | "Claude Copilot — org layer updating…" — product + layer + phase streams in | *(none — in progress)* | "This won't interrupt what you're doing." | "Sync in progress — <product>/<layer> <verb>/<phase>." |
| **Signed-out** (Auth-needed) | "CLI Copilot — department layer needs sign-in. Everything else is up to date." | "Sign in…" | *(names the product + layer that needs it)* | "CLI Copilot department-layer auth expired for <user> — awaiting device-flow sign-in." |
| **Needs-attention** (Needs-you) | "Codex Copilot — foundation layer needs a repair. Everything else is up to date." *(names the finding + product + layer)* | "Repair…" | "This fixes it for you — no terminal needed." | "Codex Copilot/<layer>: <finding-id> failed auto-repair — <one-line finding>." |
| **Update-available** (Holding) | "Knowledge Copilot — an update is available for the org layer." | "What changed?" | *(never an approve button; names product + layer)* | "Update available — <product>/<layer>; <n> machines eligible." |
| **Update-available / held** (Blocked) | "Claude Copilot — an org-layer update is waiting on IT." | "What changed?" *(informational only)* | "Nothing you need to do." | "Held for approval — <product>/<layer> major bump <old>→<new>; <n> machines waiting." |
| **IT-config-incomplete** (Holding) | "Your IT setup isn't finished yet. Nothing for you to do — IT has been told." | *(none)* | *(never Healthy, never a hang)* | "Config incomplete: required key `<key>` absent/malformed. Escalated to AdminContact." |
| **Waiting-for-network** (Holding) | "I've set up as far as your network allows. I'll finish your company setup when you're back online." | *(none)* | *(no scary error, no false-Healthy)* | "Foundation-only complete; company layers pending network (seed: <url|solo>)." |
| **Offline** (Holding) | "You're offline — showing your last synced setup." | *(none)* | "This restores on its own when you reconnect." | "Offline — rendering cached state; last good sync <ts>." |
| **Setup-needed** (Holding) | "Let's set up your copilot." | "Finish setup…" | *(slow-pulse hollow glyph)* | "Wizard not completed on <machine>." |
| **CLI-unreadable / Error** (Error) | "Versions don't match — click to update." | "Update now" *(or "Reinstall")* | "I can't read this safely, so I won't guess. Updating fixes it." | "Schema out of range / `cli-spawnable` fail — paired self-update offered. Never rendered Healthy." |
| **Updating-app** (Working) | "Updating Control Tower…" | *(none)* | *(if a bad update rolls back, see rollback copy)* | "Self-update staging; watchdog gating on liveness heartbeat." |

**Per-product × per-layer attribution is mandatory (E21, US-B08).** The single glyph shows the worst
state across all products × all layers (worst-wins, **unchanged**), but the sentence always names *which
product* and *which layer*, and reassures that everything else is up to date. Product is **data** —
these templates take a `{Product}` and a `{Layer}` variable and work for **any** declared product
(Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot are the initial set, not a hardcoded
list). `{Layer}` ∈ {foundation, org, department, personal}; a temporary department project reads as
`"{Product} — {ProjectName} (a department project) needs …"`.

- One product+layer affected: `"{Product} — {Layer} layer needs {sign-in|a repair}. Everything else is up to date."`
- Whole product up to date: `"{Product} — up to date across all 4 layers."`
- A layer updating/repairing in the background: `"{Product} — {Layer} layer updating…"` / `"{Product} — repairing {Layer} layer in the background."`
- Multiple products affected: `"{ProductA} and {ProductB} both need sign-in."` (name each; never blend into "some products")
- Dept project affected: `"{Product} — {ProjectName} (a department project) needs a repair."`

*(Replaces the retired host templates. "Foundation" is now a named per-product layer, so the old
"shared component" phrasing is gone — say `"{Product} — foundation layer needs a repair."`)*

**VoiceOver / accessibility label** on the tray glyph reads the *current status sentence*, never "app
icon" (a11y rule 2, `50-ux-design.md`). Example spoken label: *"Control Tower: CLI Copilot, department
layer needs sign-in, everything else is up to date. Press to open."* Each **product row** reads its own
label (*"Knowledge Copilot — up to date across all 4 layers"*), and each **expanded layer** reads its
own (*"Org layer — updating in the background"*).

### B. The setup wizard

#### B1. Silent managed path (0 questions — MTM-1, Flow 1)

Bob is asked nothing; he watches a progress view with the current phase named.

| Surface | Copy |
|---|---|
| Window title (header chrome — the product name Bob sees) | "Copilot Control Tower" |
| Subhead | "Setting up your copilot. This is automatic — you don't need to do anything." |
| Phase line (streams — one per product, generalized `"Setting up {Product}…"`) | "Checking your Mac…" → "Setting up Knowledge Copilot…" → "Setting up CLI Copilot…" → "Setting up Claude Copilot…" → "Setting up Codex Copilot…" → "Getting your team's setup…" → "Almost there…" *(products are data — the list is whatever the ecosystem declares, not a fixed four)* |
| No-time promise | *(no time estimate, ever — never "about 2 minutes")* |
| Resume-after-quit (E4) | "Picking up where we left off." *(headless; shown only if the window is open)* |
| Completion → teach panel | see **B3** |

#### B2. Unmanaged guided path (≤3 questions — Flow 2)

| Surface | Copy |
|---|---|
| Welcome title (header shows "Copilot Control Tower") | "Welcome to Copilot Control Tower. Let's set up your copilot." |
| Welcome body | "A few quick questions, then it runs itself. No terminal, no setup files." |
| Q1 — host choice (only if ambiguous) | Title: "Which one do you want to set up?" · Options: "Claude" · "Codex" · "Both" · Helper: "You can add the other one later." |
| Q2 — sign-in (device flow) | Title: "Sign in to continue." · Body: "We opened your browser. Enter this code there:" · `[ AB12-CD34 ]` `[Copy]` · Waiting state: "Waiting for you to finish in the browser…" · Helper: "This is the sign-in for your AI host — the same account your company uses." |
| Q3 — company + department | Company field label: "Your company" · prefilled + "Is this right?" · Department label: "Your team" · numbered pick-list · Helper: "Pick your team so you get the right setup. Not sure? Ask whoever set up your account." |
| Products step (narrow-only) | "These come with your team's setup. Uncheck anything you don't want." *(Bob can narrow, never widen — no "add more" affordance.)* |
| Progress | reuse **B1** phase lines. |

#### B3. Teach panel (shown once after first success — US-B06)

| Surface | Copy |
|---|---|
| Title | "You're set up." |
| Body | "Your copilot is ready and will keep itself up to date. Here's the one-page cheat-sheet to get started." |
| Actions | "Open cheat-sheet" · "Add your first skill" · "Turn on backup" |
| Backup offer body | "Want a backup of your setup? It's optional and takes one click." |
| Dismiss | "Done" |

> **Understatement rule (Alert Machine).** The completion state is "You're set up.", not
> "🎉 Congratulations! You're all set!". No confetti, no streaks, no "great job".

#### B4. Honest holding screens inside the wizard

| Screen | Title | Body |
|---|---|---|
| IT-config-incomplete (E1) | "We're waiting on IT" | "Your setup isn't finished because IT hasn't sent one piece yet. There's nothing for you to do — IT has been told automatically." |
| Waiting-for-network (E2/E3) | "You're offline" | "I've set up as far as your network allows. I'll finish your company setup on its own when you reconnect." |

### C. Escalation-to-IT messages (Admin surface + AdminContact channel)

These are **IT/Admin-facing**. They are content-free about Bob's personal data by construction
(E17/E20) — they name the machine and the condition, never a personal item name.

| Trigger | Escalation copy (IT) |
|---|---|
| Config incomplete (E1) | "Setup blocked on <machine>: required key `<key>` is missing or malformed. This Mac is holding at *IT-config-incomplete* and will not go Healthy until it's fixed." |
| Security auto-suspend (MTM-3 / E8) | "Kept a machine safe: a security fix on <machine> replaced a component the user had overridden. The override was auto-suspended; the fixed version is live." |
| Persistence disabled (E13) | "Startup was turned off on <machine> — it may stop staying up to date. This isn't the same as a powered-off Mac; the login item needs re-enabling (or enforce it via the managed payload)." |
| Time-boxed Bob item (E16) | "<machine> hasn't been backed up in 7 days — the reminder to the user has gone unanswered, so it's now with you." |
| Held-major (MTM-4 / E10) | "A major update is waiting on your approval: <old> → <new>, <n> machines affected. Review before rollout." |
| Safety escalation reached (E17) | *(delivery is on-by-default for managed via mandatory AdminContact — "IT notified" is never a no-op.)* |

### D. Auth / re-login prompt (the one recurring Bob credential moment — E22, Flow 8)

The **one** kind of thing Bob is asked about, because it's his own data and only he can do it.

| Surface | Copy |
|---|---|
| Status line | "CLI Copilot — department layer needs sign-in. Everything else is up to date." |
| Notification (only if his to act) | "CLI Copilot needs you to sign in again for its department layer — it's a quick browser step." |
| Sign-in sheet title | "Sign in for CLI Copilot" |
| Sign-in sheet body | "We opened your browser. Enter this code there:" `[ AB12-CD34 ]` `[Copy]` |
| Waiting | "Waiting for you to finish in the browser…" |
| Success | "Signed in. CLI Copilot's department layer is back to normal." |
| If it's a *machine* credential (not his) | *(no Bob prompt — routes to IT: "A machine credential on <machine> needs renewing (<product>/<layer>).")* |

### E. The commit-your-work interruption (the only confirmation Bob ever sees — Flow 8 / E22)

| Surface | Copy |
|---|---|
| Notification / popover | "You have unsaved personal work. Save or commit it, then I'll sync." |
| Why (helper) | "I never touch your own files without you." |
| After he commits | *(silent resume — the sync just proceeds)* |

### F. The security auto-suspend "kept you safe" line (MTM-3 / Flow 7)

Shown to Bob only *if and when he opens the dropdown* — quiet, past-tense, never a live interruption
or a badge to clear.

- **Bob:** "Kept you safe — a security fix replaced a component you'd overridden. Re-affirm your
  version ▸"
- **IT (parallel, immediate):** see **C** → "Kept a machine safe…".

---

## Microcopy Patterns

### Errors

**Structure:** *[What's true, plainly] + [what happens next / the one thing to do]* — **never blame
Bob, never a code, never alarm words.** The app failing to *read* something is stated as the app's
limit ("I can't read this safely"), not the user's fault.

| Condition (scenario) | Bob copy | IT copy |
|---|---|---|
| Schema drift / unreadable `--json` (E6) | "Versions don't match — click to update. I won't guess when I can't read this safely." | "Schema out of app range; paired self-update offered. Rendered *Error*, never Healthy." |
| Vendored engine won't start (E5) | "I couldn't start the engine. Click to reinstall — it's a fix, not a reset." | "`cli-spawnable` fail (likely Gatekeeper quarantine). De-quarantine on reinstall." |
| Bad self-update (E14) | "Kept your working version — an update didn't start cleanly, so I rolled it back. Nothing broke." | "Staged bundle failed liveness gate; discarded and poisoned. Working version retained." |
| Config incomplete (E1) | "Your IT setup isn't finished yet. Nothing for you to do — IT has been told." | "Required key `<key>` absent/malformed → *IT-config-incomplete* + AdminContact." |
| Sign-in expired (E22) | "CLI Copilot — department layer needs sign-in. Everything else is up to date." | "Auth expired for <product>/<layer> — device-flow re-sign-in pending." |
| A used tool was pruned (E11) | "A tool you'd been using was removed in the latest update." | "Prune of recently-used item surfaced to user; zero-usage prunes stay silent." |
| Offline (E2) | "You're offline — showing your last synced setup. This fixes itself when you reconnect." | "Offline; cached render; auto-recovers on reconnect." |

> **What we never do in an error:** blame ("You entered the wrong…"), alarm ("CRITICAL", "DANGER",
> "FATAL", "❌ ERROR"), leak jargon ("exit code 2", "flock", "schema"), or promise a human
> ("contact support") when the app can fix it in place.

### Success States

**Understated by design (Alert Machine, principle P1).** The success state is usually *silence*. When
a confirmation is genuinely useful, it's a plain past-tense sentence — never a celebration.

| Moment | Copy |
|---|---|
| Steady-state healthy | *(nothing — no toast, no "all good", no green cheer)* |
| A sync finished | *(nothing; glyph simply returns to solid)* · if the dropdown is open: "{Product} — up to date across all 4 layers." |
| First setup done | "You're set up." *(teach panel — B3)* |
| Sign-in worked | "Signed in. CLI Copilot's department layer is back to normal." |
| Rollback protected them | "Kept your working version. Nothing broke." |
| Security fix auto-applied | "Kept you safe — a security fix replaced a component you'd overridden." |

> **Banned in success:** "🎉", "Congratulations!", "Awesome!", "You're all set!", "Great job!",
> "Streak", "Level up". Understatement *is* the brand.

### Loading & Processing

**Reassuring, brief, honest about phase — never a fake progress theatre, never a time estimate.**

| Moment | Copy |
|---|---|
| Wizard phases | "Checking your Mac…" · "Setting up {Product}…" (per declared product) · "Getting your team's setup…" · "Almost there…" |
| Steady-state sync | "{Product} — {Layer} layer updating…" (e.g. "Claude Copilot — org layer updating…") |
| App self-update | "Updating Control Tower…" |
| Resuming after a quit (E4) | "Picking up where we left off." |
| Reduced-motion fallback | *(the spinning ring becomes a static state + the word "Syncing…" — motion is never the only signal, a11y rule 7)* |

> No spinner ever sits under a false claim. "Syncing…" means a real CLI verb is in flight; it is a
> reassurance, not an alarm, and it never blocks what Bob is doing.

### Empty States

**Structure:** *[What's here] + [why it's empty] + [the one next action]* — optimistic and guiding,
never a dead end.

| Surface | Copy |
|---|---|
| No skills added yet (Bob) | "No skills yet. Add your first one to give your copilot something to do." · `[Add a skill]` |
| "What changed" with nothing to show | "Nothing's changed since your last look. You're up to date." |
| Fleet dashboard, no machines yet (IT) | "No machines are reporting yet. Once you push the app and profile, they'll self-provision and appear here." |
| Govern queue, empty (IT) | "Nothing waiting on you. Held updates and time-boxed items will show up here." |
| Preflight not yet run (IT) | "No preflight yet. Run it to check your seed, repos, policy, and profile before you deploy." |
| Version-skew, all on current SHA (IT) | "Every machine is on the current version." |

---

## Banned Language

Explicit stop-list. Left column never appears **anywhere**; the middle notes any Bob-only vs
IT-allowed nuance.

| Banned | Register scope | Why |
|---|---|---|
| "All good" / "Everything's fine" / "No problems!" as a blanket claim | Everywhere | The core promise is *the icon that cannot lie*. A blanket reassurance is exactly the false-Healthy the product exists to prevent. State only what the CLI proved. |
| "Healthy" when it can't be proven | Everywhere | Same. Offline/mid-setup/unreadable → an honest holding state, never "Healthy". |
| "CRITICAL", "DANGER", "FATAL", "URGENT", "❌", red-alert theatre, all-caps warnings | Everywhere | *The Alert Machine.* Alarm burns the credibility of the one alert that matters. Failures are stated calmly. |
| "Congratulations!", "🎉", "Awesome!", "You're all set!", "Great job!", "Streak", "Level up", gamification | Everywhere | Understatement is the brand; celebration cheapens trust and manufactures engagement the product refuses. |
| "Act now", "Immediately", "before it's too late", countdowns, fake urgency | Everywhere | Manufactured urgency is dishonesty. Real security events are *auto-acted*, not urgently delegated. |
| "YAML", "flock", "exit code", "schema", "daemon", "CLI", "repo", "SHA", "mobileconfig", "profile key", "stderr" | **Bob only** (IT-allowed) | Bob never learns these words. Same fact for IT can be precise. |
| "The AI decided / determined / knows / thinks / figured out" | Everywhere | The app *parses*, never computes a verdict. It renders the CLI's truth; it never claims judgment. |
| "Auto-resolved", "second brain", "smart health check", "it detected a problem and fixed it itself" (as the app's own act) | Everywhere | Same — implies the app computed. Say "synced", "updated", "kept you safe" (past-tense of a CLI action). |
| "Review and approve — or wait for IT" (to Bob) | **Bob only** | *The Alert Machine / MTM-4.* Bob has no basis to judge a held-major. His view is "waiting on IT"; no approve control exists. |
| "Something needs your attention" / "One or more issues" / any blended verdict | Everywhere | Must name the *specific* failing **product and layer**. A blur is a design failure (Quality Bar). |
| "Error", "Failed", "Warning" as a bare label | Everywhere | Always pair with what's true and the next step; never a naked scary word. |
| "Contact support", "call IT", "run doctor in a terminal", "open Terminal" | **Bob only** | Bob has no terminal. In-app recovery ("click to update / reinstall") replaces every terminal instruction. |
| "You entered the wrong…", "Invalid input", any blame | Everywhere | Never blame the user. State the condition and the fix. |
| "Force", "Skip verification", "Override", "Make it healthy anyway", "Unstick it" | Everywhere | No bypass affordance exists (invariant #4 / *Convenience Backdoor*); the words for it must not exist either. |
| "Aviator" | Everywhere | Dead engineering-only codename — must never appear as a product name on any user surface. The product name is "Copilot Control Tower" (short "Control Tower"), shown to both Bob and IT. The aviator-*sunglasses mark* is the tray glyph; the *word* "Aviator" is banned. |
| Time estimates ("about 2 minutes", "~30 seconds", "almost done in…") | Everywhere | Per brief: no time estimates. Use phase names ("Almost there…"), never a clock. |

---

## Implementation Notes

- **Register enforcement.** Strings are keyed by surface; the Bob register and IT register are
  *separate keys for the same event*, never one string down-leveled at runtime. A build-time lint
  should reject any Banned-Bob term appearing in a Bob-register key.
- **Dynamic content.** `{Product}` is **data** — any declared product (initial set: Knowledge Copilot,
  CLI Copilot, Claude Copilot, Codex Copilot), never a hardcoded enum; `{Layer}` ∈ {foundation, org,
  department, personal}; `{ProjectName}` is a temporary department project scoped under the department
  layer. The "everything else is up to date" clause is emitted **only** when every *other* product ×
  layer actually parsed Healthy (never asserted — worst-wins honesty, P2). `<key>`, `<machine>`, `<n>`,
  `<old>→<new>` are IT-register only and never leak into a Bob string. Personal item names are
  **un-emittable** in any escalation by construction (E20) — no template accepts one.
- **VoiceOver.** Every status has an accessibility label = its Bob top line (naming product + layer);
  **every product row** carries its own label ("Knowledge Copilot — up to date across all 4 layers");
  **every expanded layer row** carries its own ("Org layer — updating in the background"), and the
  product row exposes its expanded/collapsed state. Every action row names its action + plain-language
  effect ("Repair — fixes the thing IT can see"). Status transitions post an announcement (a11y rules
  2–3).
- **Character limits.** Status top line targets ≤ ~60 characters (one glanceable sentence, ~320pt
  popover width). Notification title/body follow macOS limits. <!-- TODO: confirm exact truncation
  width against the shipped popover + notch layout. -->
- **Localization.** English strings are the source. The per-product × per-layer attribution template —
  "{Product} — {Layer} layer needs X. Everything else is up to date." — must survive translation
  without re-blending into a single vague verdict, and must keep `{Product}` and `{Layer}` as
  independent, ordered variables (product then layer). Flag for translators that *naming both the
  product and the layer is load-bearing*, not stylistic. <!-- TODO: confirm target locales for v1. -->
- **Product name — RESOLVED.** The product name is **"Copilot Control Tower"** (short: **"Control
  Tower"**), per `00-overview/00-vision.md`, and it **is shown to the end user**. Bob sees the full
  name in the **setup-wizard header**, the **dropdown/popover header**, and **About**; IT/Admin copy
  uses "Control Tower". The name is **not** hidden from Bob — but it lives in the **chrome**
  (wizard/header/About), **not** jammed into every status line. Status *sentences* stay about Bob's
  work — calm and honest ("CLI Copilot — department layer needs sign-in.") — never a brand line. The
  **aviator-sunglasses mark** is the menu-bar glyph Bob sees; **"Aviator"** is a dead engineering-only
  codename that must never appear as a product name on any user surface (see **Banned Language**).

---

**Related:** [UX Design](50-ux-design.md) · [Moments That Matter](../02-service-design/40-moments-that-matter.md) ·
[Use Cases & Scenarios](../03-requirements/20-use-cases-and-scenarios.md) ·
[Vision](../00-overview/00-vision.md) · [SOUL](../../../SOUL.md)
