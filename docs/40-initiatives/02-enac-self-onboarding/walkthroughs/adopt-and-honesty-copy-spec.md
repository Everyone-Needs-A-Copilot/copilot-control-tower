# Copy spec: the adopt offer, honest incompleteness, and the missing GitHub permission

> **Working design doc, carried forward from the session scratchpad so it isn't lost.** This is the spec behind commits `9d4730f` (`fix(app): offer the connection you already have, and stop claiming setup finished`) and `a3884b0` (`fix(app): remind people about the permission only they can grant`), the second and third of a five-commit sequence that starts with `holding-copy-spec.md` (this same directory) and continues through `org-question-copy-spec.md`. The ratified, current state of everything below lives in `docs/03-design/control-tower-copy-deck.md` (§2.2.1 the adopt offer, §2.9's H7 row and §2.9.3, §2.10 the completion rule) — treat this file as the historical record of the reasoning that produced it, not as the live spec. See `docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-honest-setup-work-record.md` for the work-record account.

Final UX copy for three new states in the Copilot Control Tower first-run wizard. Every string below is final and verbatim-ready. An implementer follows this literally; nothing here needs interpretation, and nothing here is a suggestion.

**Target file for the copy itself:** `/Volumes/Dev/Sites/COPILOT/copilot-control-tower/docs/03-design/control-tower-copy-deck.md`
**Code that renders it:** `/Volumes/Dev/Sites/COPILOT/copilot-control-tower/native/wizard.swift`
**CLI that supplies the dynamic strings:** `/Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc/src/cc/core/ecosystem/ssh_identity.py` and `/Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc/src/cc/commands/onboard.py`

---

## 0. Why this change exists

The wizard had a dead end. A person whose Mac already had a working GitHub connection was stopped at stage 3 of 8 with a Holding screen reading *"Something here is already yours"* and a primary button reading *"Keep what I have"*. Clicking it showed *"Kept as it is. Control Tower keeps watch from the menu bar and picks this up if it ever changes."* and left setup two-thirds unfinished while looking resolved.

That is the failure being fixed, and it is worth naming precisely: **a calm screen over an unfinished setup is worse than an obviously broken one, because the person walks away believing they are done.**

The CLI has been fixed to verify-and-adopt instead of blocking. It tests whether the existing connection actually works, confirms it signs in as the same GitHub account, and if so offers to adopt it and add only what is missing, touching nothing that already works.

Three states follow from that fix. State 1 is the offer that replaces the dead end. State 2 is the pattern that makes a fake-resolved confirmation impossible anywhere in the wizard, which is the durable fix. State 3 is a real defect the old bug was masking.

### The three governing constraints

1. **Repo `CLAUDE.md` invariant #1, parse never compute.** The app renders the CLI's `--json` and shells out. It implements no resolution, no auth, and no decision logic of its own.
2. **Repo `CLAUDE.md` invariant #3, never-destroy.** The app never touches a dirty personal working tree and never overwrites what it did not create.
3. **Repo `CLAUDE.md` invariant #5, route by actor-competence x reversibility.** Who owns the fix determines who the message is addressed to. Auto-act on reversible things the person cannot judge, escalate to IT what they cannot action, and ask the person only about non-deferrable decisions on their own data.

### Voice rules that bind every string here

First person. Sentence case. Warm and factual. No exclamation marks. No em-dashes. No blame. No time estimates. Titles 50 characters or fewer. Buttons are verbs and never `OK`, `Dismiss`, `Close`, `Retry`, `Repair`, `Fix`, or `Force`.

The product's spec **is** the non-technical user. Never surface `rank`, `manifest`, `package`, `tier`, `alias`, `SSH`, `scope`, `token`, `OAuth`, or `device` as a user-facing word. `key` is permitted and is the settled word for what this Mac is given.

### Three findings from the code that shape every decision below

1. **The adopt offer cannot be a Holding variant.** `ensure_machine_ssh_identity` returns `result: "changes-required"` on plan and `"applied"` on apply, with `config: "adoptable"`. It never returns `"blocked"` on this path. `WizardModel.performDetect`'s blocked-guard therefore never fires and `holdingInfo(forBlockedOnboard:)` is never called. The state is structurally unreachable from Holding. It is already an offer at the contract level.
2. **The CLI already emits the exact DTO the existing question screen renders.** `_ssh_inventory` in `onboard.py` deliberately mirrors `_personal_inventory`: `state: "adoptable"`, `action: "create"`, `reversible: true`, plus `detail` and `decline_detail`. The one difference is `scope: "machine"` rather than `"personal"`.
3. **State 3 has no signal to render today.** `_github_keys` collapses every `gh api user/keys` failure, including the 404 that means a missing `admin:public_key` permission, into one sentence with `config: "planned"`. That lands on H3's *"I couldn't give this Mac its own key"*, a fault addressed to nobody, for a fix only the person can make.

---

# STATE 1 — The adopt offer

## 1.1 Where this belongs: reuse "One question first". Do not build a new screen.

**Decision: reuse the existing inline-over-Detect "One question first" screen.** It is specified in `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-project-setup-spec.md` under "One question first (inline over Detect)" and built at `native/wizard.swift:2274`. It is **not** a Holding variant and must never become one.

Four reasons, in order of weight:

- **The contract is identical.** The SSH row is the same DTO shape as an adoptable package row, by the CLI's own explicit design. `_ssh_inventory`'s docstring says so: "An adoptable SSH alias is a pure offer (B1), the same shape as an adoptable personal package." A second screen would render the same fields with different words.
- **The decision is identical.** "You already have something. May I keep it and add what's missing?" Asking that twice in one wizard, on two surfaces, is exactly the fragmentation the H4 rewrite just removed.
- **It never reaches Holding.** `changes-required` is not `blocked`. Routing an offer through a pause screen would be the same lie in a new costume.
- **The way back already exists.** Cleared rows already reveal `decline_detail`, and `Not now` already re-plans.

The screen needs **one structural change**: it is no longer GitHub-account-scoped. It gains a second card for machine-scope rows and a scope-aware intro.

## 1.2 Final copy

**Eyebrow** (unchanged): `ONE QUESTION FIRST`

**Title** (CHANGED): `Want me to include what you already have?`

> Changed from `You already have some of this. Want me to include it?`, which is 53 characters and over the 50-character rule, and whose first sentence repeats what the cards below already show. The question is the whole point of the screen, so the question is the title. The new title is 41 characters and works unchanged for both scopes.

**Intro**, one of exactly three, chosen by which scopes are present among the ask rows:

| Rows present | Intro |
|---|---|
| GitHub-account rows only (`scope: "personal"`) | `Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone.` |
| This-Mac rows only (`scope: "machine"`) | `This Mac is already set up to reach GitHub, and I checked that what's here works. I can build on it, or leave it alone and set the rest up around it.` |
| Both | `You already have some of this: spaces of your own on GitHub, and a working connection on this Mac. I can build on what's here, or leave it alone and set up the rest around it.` |

**Card 1 label** (unchanged, holds every `scope: "personal"` row): `Already in your GitHub account`

**Card 2 label** (NEW, holds every `scope: "machine"` row): `Already on this Mac`

**Row title** for the machine row (CLI `title`, rendered verbatim): `Your Mac's connection to GitHub`

**Row caption** for the machine row (CLI `detail`, rendered verbatim):

`This Mac already connects to GitHub, and I checked that it works and that it's signed in as you. I'll leave that exactly as it is and add the one connection it's still missing.`

**Cleared-row caption** for the machine row, revealed under the row when the checkbox is cleared (CLI `decline_detail`, rendered verbatim):

`Without this, this Mac keeps one of the two GitHub connections setup uses. Setup carries on, and I'll offer this again from the menu bar whenever you're ready.`

**Quiet line under the cards, always present** (CHANGED): `Nothing you already have is changed. Setup only adds what's missing.`

> Changed from `Nothing existing was changed.`, which carried only half the promise and let a never-destroy screen read as a refusal.

**Review rows** (any item with `action == "review"`): unchanged. No checkbox, a trailing read-only label `Kept as is`, and a hand-raised glyph. Row caption is the CLI's `detail`, verbatim.

## 1.3 How "your existing connection works and I checked" gets said without jargon

The row caption above does the whole job in two sentences and five beats, none of which name a mechanism:

- **I checked** — "I checked that it works"
- **It works** — stated as a completed finding, not as a technique
- **It's you** — "signed in as you", which conveys the identity match without exposing the login, the account, or the comparison that produced it
- **I'm not touching it** — "I'll leave that exactly as it is"
- **One thing gets added** — "add the one connection it's still missing"

The verification is expressed as a **completed act**, never as a procedure. The person learns that a check happened and passed. They never learn what was checked, and they do not need to.

Words that must never appear in this string or anywhere near it: `SSH`, `alias`, `key pair`, `host`, `hostname`, `remote`, `handshake`, `credential`, `github-work`, `github-personal`, or any GitHub login.

## 1.4 ADDED versus LEFT ALONE: two ideas, two surfaces, never merged

These are two distinct ideas and they live on two distinct surfaces, deliberately:

- **The row caption** (CLI-authored) carries the *specific found fact*: this exact thing was checked, it works, it stays, and this exact thing gets added.
- **The quiet line under the cards** (app-authored) carries the *general guarantee*: nothing you already have is changed, and setup only adds what is missing.

**Never merge them.** The never-destroy promise is the reassurance and it must not depend on the CLI getting a sentence right. The app-authored line is structurally true for every row with `action: "create"` and `reversible: true`, so it cannot drift from what the CLI actually does. The CLI-authored line is specific and therefore fallible; it is where the *ask* lives, not where the *promise* lives.

Ordering within the row caption is also deliberate: **left-alone first, addition second.** The reassurance lands before the request.

## 1.5 Buttons

| Label | Role | What happens after |
|---|---|---|
| `Include what I have` | **Primary**, default keyboard action | The app sends exactly the checked rows as `--adopt-existing`, re-runs the read-only plan behind the progress card `Checking what that means…`, and lands on Detect's result screen. On the later apply, the CLI writes only the missing connection and never touches the verified one. |
| `Not now` | Leading | The app runs the same re-plan without those tokens. Setup continues to Detect and onward through every remaining step. The offer moves to the menu bar. |

Primary disabled hint, shown when every row is cleared (unchanged): `Choose something to include, or select Not now.`

`Include what I have` survives the widened scope without a rewrite: adopting the working connection *is* including what he has. Introducing a second primary for one row would split one decision into two.

Rows are independently decidable. The primary includes exactly the selected rows; every cleared row is declined for this run. There is no all-or-nothing choice, and no row is hidden because another row is worse.

## 1.6 The decline path, and why it is not a dead end

Declining costs nothing structural. The re-plan comes back `changes-required`, and setup finishes everything else. This is the honest framing and it must not be dressed up as worse than it is.

To keep the CLI's own decline sentence honest ("I'll offer this again from the menu bar whenever you're ready"), Region 6 of the menu-bar popover gains **one notice**:

- Notice message: `This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.`
- Action label: `Add the connection`

**A notice, not a prompt.** An offer the person already declined is not a fault, and re-prompting is nagging. This is the same call the projects offer made, and the reasoning is recorded there: "a project that can have copilots is an offer, not a fault." Region 5's closed action set stays closed, and no badge appears on the menu-bar glyph.

Without this row, `Not now` is permanent and the CLI's decline sentence is a lie. This is the only net-new menu-bar element in the entire spec.

---

# STATE 2 — Honest incompleteness

## 2.1 The completion rule (this is the real deliverable)

This rule is checkable by an implementer. It is not a vibe, and it must be enforced as a branch in code, not as an editorial habit.

> **The completion rule.** A screen may use resolved language — *kept*, *done*, *set up*, *ready*, *checks out*, *everything*, *all* — only when all four of these hold of the report it is rendering:
>
> 1. `result` is `applied` or `ready`. Never `changes-required`, never `blocked`.
> 2. No entry in `stages` has `result: "blocked"`.
> 3. Every stage in `onboard.schema.json`'s `ecosystemStage.stage` enum appears in `stages`. A stage the report never mentions counts as not done. `SetupProgressState.resolveStageRows` already computes exactly this and calls it `.neverReported`.
> 4. The sentence describes only what the report proves. A confirmation may resolve **the decision the person just made**. It may never resolve **setup** on the strength of that decision.
>
> If any one of the four fails, the screen renders the §2.2 pattern instead. The app never softens a failing condition with a gentler adjective. It switches patterns.

**Applied to the bug being fixed:** `Keep what I have` is reachable only from H4, and H4 is reachable only when `report.result == .blocked`. Condition 1 can therefore never hold at that moment. **`Kept as it is` is withdrawn, not conditioned** — it was unreachable-as-true from the day it was written, and conditioning it would imply a passing case exists.

**Condition 4 is the one that matters most.** It catches the class of bug rather than the instance. "Kept as it is" was true about the decision and false about setup, and it printed only the true half. Any screen that answers a decision while setup is unfinished must say both things: what the decision did, and what setup still has not done.

## 2.2 The pattern: "I stopped, and here's what that means for you"

This is the pattern every terminal confirmation in the wizard falls back to when the completion rule fails.

**Eyebrow:** `SETUP ISN'T FINISHED`

**Title:** `Here's where that leaves you`

**Intro**, one of exactly two:

| Reached from | Intro |
|---|---|
| A decision the person just made, such as `Keep what I have` | `I left your own things exactly as they were. Setup stopped there, though, so some of this isn't set up yet.` |
| Anywhere else | `Setup stopped partway, so some of this isn't set up yet. Nothing that was already on this Mac was changed.` |

**Two cards, in this order:**

- Card 1 label: `What works now`
- Card 2 label: `What doesn't work yet`

Card 1 empty body: `Nothing yet. Setup stopped before anything was put in place.`

If Card 2 would be empty, the completion rule passed and **this screen must not render at all.**

**Quiet line under both cards:** `Nothing you already had was changed, moved, or removed.`

**Repeat caption** (unchanged, shown from the second consecutive identical state onward): `Still the same. Nothing changed.`

## 2.3 Capability framing: the row copy

The person will not understand stage names, and must never see them. Each row is a capability sentence in words they own, selected by the CLI's `stage` enum token. This is a **closed app-authored set keyed on a CLI token**, which is the same discipline the deck's §1.2 reason table already uses. Never render the stage's `detail`, never render the stage id, and never render a gerund.

| `stage` | In `What works now` | In `What doesn't work yet` |
|---|---|---|
| `organization-handoff` | `Your organization's shared setup came through.` | `Your organization's shared setup hasn't come through.` |
| `personal-packages` | `Your own spaces on GitHub are ready.` | `Your own spaces on GitHub aren't ready yet.` |
| `device-ssh` | `This Mac can reach GitHub on its own.` | `This Mac can't reach GitHub on its own yet.` |
| `layer-manifest` | `Your copilots are connected together.` | `Your copilots aren't connected together yet.` |
| `secret-store` | `The integrations your team shares are ready.` | `The integrations your team shares aren't ready yet.` |
| `codex-plugin` | `Codex Copilot is set up on this Mac.` | `Codex Copilot isn't set up on this Mac yet.` |
| `materialize` | `Your copilots are in place on this Mac.` | `Your copilots aren't in place on this Mac yet.` |
| `doctor` | `Everything checked out as current.` | `I couldn't confirm your copilots are current.` |

**A stage that never ran and a stage that ran and failed take the same line.** The difference is invisible to the reader and belongs in the support block, not on the screen. This is checkable: a `.neverReported` row and a `result: "blocked"` row both render the right-hand column.

## 2.4 Partial progress: no fraction, ever

**Decision: do not show "3 of 8 done".** Not as a fraction, not as a bar, not as a ring, not as a percentage.

Justification, four points:

1. **A fraction answers a question the person did not ask.** They want to know whether they can use their copilots. A fraction cannot tell them: five trivial stages done and three load-bearing ones missing scores identically to the reverse.
2. **The deck already refuses this shape.** Hard rule 7 bans percentage-as-a-promise. §2.6 permits `Part N of M` only as **in-flight phase position**, never as an outcome. A fraction on a terminal screen is a score.
3. **The precedent is settled even for the technical user.** §3.12 gives Earl "a plain count, no score, no percentage, no gauge" on the admin setup check. Earl acts on counts because he can act on the underlying items. The non-technical person cannot, so he gets capability instead.
4. **A fraction invites him to judge severity.** Judging is precisely what this product refuses to hand him (invariant #5, and SOUL's "never asked to judge").

The two named capability lists carry everything a fraction would, in words he owns, and they carry it without asking him to score anything.

## 2.5 The action: make the handoff obvious, not hidden

Where there is no self-service fix, the honest answer is to hand it to whoever supports their Mac.

**Caption above the footer:** `Whoever looks after your Mac can pick this up from here.`

| Label | Role |
|---|---|
| `Copy details for support` (confirmed: `Copied`) | **Primary** |
| `Try again` | Leading |
| `Continue in the menu bar` | Leading |

The clipboard contents are exactly the block defined in the deck's §2.9.1 `Details for support`, unchanged.

**`Details for support` stays collapsed and never self-expands.** That rule is unchanged and correct. Prominence comes from the **button**, not from forcing the block open. The person who needs to hand it over copies it in one click without reading a line of it; the person who wants to inspect it still can. That satisfies both the disclosure rule and the requirement that the handoff be the obvious next step rather than a hidden disclosure.

**One branch, checkable:** when the current plan still carries ask rows (any inventory item with `reversible == true`), the primary becomes `Include what I already have` and `Copy details for support` moves to the leading row. A user-owned way forward always outranks a handoff.

`Continue in the menu bar` never marks setup complete. After this screen, the tray keeps rendering whatever the CLI reports, which by construction is not `Everything is set up.` That was the original failure: a calm surface over an unfinished machine.

## 2.6 Where the pattern applies

- **H4's `Keep what I have` confirmation: always.** The old `Kept as it is` screen is deleted.
- **§2.7 Verify's `Everything checks out.`:** permitted only when the completion rule passes. If it does not, Verify renders this pattern instead. There is no hedged middle wording.
- **§2.8 Done:** unchanged, because Done is reached only through a passing Verify. The rule now makes that dependency explicit rather than incidental.

---

# STATE 3 — Missing GitHub permission

## 3.1 The defect

Verified on the real machine: `gh api user/keys` returns 404 because the signed-in GitHub token lacks the `admin:public_key` permission. Setup cannot register this Mac's key without it. This was always broken; the old dead end masked it.

Today `_github_keys` returns `"GitHub could not list SSH keys for the authenticated account."` with `result: "blocked"`, `registration: "not-checked"`, `config: "planned"`. The app's gate table sees `device-ssh` with `config != "held"`, falls through to H3, and shows *"I couldn't give this Mac its own key, so I stopped."* That is a fault variant addressed to nobody, for a fix only the person can make. It is wrong in both directions.

## 3.2 Decision: this is a new Holding variant, H7

The taxonomy's own rule is that the variant follows **who owns the fix**, never what went wrong. Run that test against all six existing variants:

- **H1 (not installed)** — the owner is whoever installs software on this Mac, possibly not this person, and the fix happens outside the app.
- **H2 (can't read your setup)** and **H3 (couldn't finish a part)** — neither names an owner; both terminate in support details.
- **H4 (something is already yours)** — the owner is the person, but the frame is "nothing is wrong, decide about your own content." Nothing here is his content, and something *is* wrong.
- **H5 (waiting)** — the owner is time.
- **H6 (waiting on your organization)** — the owner is the organization.

None of the six carries *the fix is yours, it is a real fix and not a decision, and you can do it right here.* That is H7.

`SOUL.md` §7's tone table already names this exact register: for a Bob-actionable event the tone is "Direct, singular, respectful of his ownership — the one thing only he can do." The eyebrow is taken straight from that line.

| # | Variant | Eyebrow | Title | Tint | Glyph |
|---|---|---|---|---|---|
| H7 | Something only you can do | `ONE THING ONLY YOU CAN DO` | `Setup needs one permission from you` | `signed-out` `.systemBlue` | `key` |

**Tint justification:** `signed-out` blue is the visual system's own "Actionable-by-you, informational blue (not alarm)" (`control-tower-visual-system.md` §2.2). No new token, no new color, no new glyph, and the key glyph is literally the subject of the screen.

## 3.3 Final copy

**Eyebrow:** `ONE THING ONLY YOU CAN DO`

**Title:** `Setup needs one permission from you`

**Intro:** `Setup gives this Mac its own key so it can reach GitHub safely. Adding that key needs a permission GitHub hasn't been asked for yet, and you're the only one who can give it.`

Note what this avoids. No `scope`, no `token`, no `OAuth`, no `admin:public_key`. And **no blame**: the permission was never *asked for*. It is not *missing from his account*, and he did not fail to grant it. `key` is already established deck vocabulary (§2.6's `Giving this Mac its own key`), so it costs him nothing new to learn.

**Quiet caption above the footer:** `I'll take you to GitHub to grant it. Nothing on this Mac changes.`

## 3.4 Buttons

| Label | Role | What happens after |
|---|---|---|
| `Grant this on GitHub` | **Primary** | Opens the grant sheet (§3.5) |
| `Continue in the menu bar` | Leading | Closes the wizard. Never marks setup complete. |
| `Show me how to grant it` | Leading, **rendered only when the CLI reports it cannot drive the grant itself** | Opens the fallback sheet (§3.6) |

`Details for support` (deck §2.9.1) is present and collapsed on H7, because if the grant path itself fails, IT needs it.

## 3.5 The grant sheet

Verbatim reuse of the deck's §2.5.1 device-flow grammar, which the person completed two steps earlier at Connect GitHub. Only the title and the success line differ.

- Title: `Grant the permission`
- Intro: `GitHub will ask you to confirm this. Copy the code below, open the page, and paste it in.`
- Code label: `Your code`
- Copy affordance: `Copy code` / confirmed `Copied`
- Primary: `Open the GitHub page`
- Waiting line (no countdown, no timer): `Waiting for you to finish in your browser...`
- Granted: `Granted. Picking up where I left off.`
- Denied: `That was declined.` + `Try again`
- Expired: `That code expired.` + `Get a new code`
- Timeout: `That took too long.` + `Get a new code`
- Dismiss buttons: `Cancel` (while pending) / `Done` (once granted)

## 3.6 The fallback sheet

Shown only behind `Show me how to grant it`, and that button appears only when the CLI reports it cannot drive the flow. Shaped after the deck's §2.9.2 install sheet.

- Title: `Granting the permission by hand`
- Intro: `This is one command. If you're comfortable in Terminal, paste it there. If you're not, copy it and send it to whoever looks after your Mac.`
- Block label: `The step`
- Block contents (mono, never wrapped into prose): `gh auth refresh -h github.com -s admin:public_key`
- Copy affordance: `Copy this step` / confirmed `Copied`
- Primary: `Done` (closes the sheet and re-checks once, automatically)
- The H7 body itself never contains a command, a path, or the phrase `permission scope`.

## 3.7 Why a button and not a copyable command, and not a hand to IT

**Against invariant #5 (actor-competence).** The owner of this fix is the person and can be nobody else. It is a permission on *his* GitHub sign-in, and IT cannot grant it without sitting at his Mac signed in as him. Routing it to IT is not the conservative choice, it is the wrong one. §2.9.2 exists for the opposite case, and says so in its own intro: "This is one command for whoever set up this Mac." Reusing that pattern here would hand the work to an actor who cannot perform it.

So the question is not *whether* to address him but *how*. The only interaction shape he has demonstrated competence at is the one he completed two steps earlier at Connect GitHub: a code, a button, a browser page. That is why the primary is a button that runs the flow, not a command he has to type correctly.

The action is additive and reversible — permissions can be withdrawn on GitHub at any time — which places it squarely in "ask the person about a non-deferrable decision on their own data."

**Against invariant #1 (parse never compute).** The app holds no client id, performs no polling logic of its own, and implements no auth. It calls a CLI verb, renders `user_code` and `verification_uri`, and passes `device_code` back. That is byte-for-byte what `DeviceFlowState` in `wizard.swift` already does against `cc auth login --json`. The auth lives where auth lives.

**Why a copyable command as the default path fails both.** It puts jargon on the one surface that must not carry it, and it makes the app's success depend on him not mistyping a flag.

---

# APPENDIX D — CLI strings and contract additions this change requires

Detect rows, ask rows, and framed Holding details are printed straight from the CLI, so those strings are user-facing copy and must obey the same closed vocabulary as the app's own. This is established practice: the adopt-and-project-setup spec already carries a table of exactly this kind.

`ssh_identity.py` and `onboard.py` currently emit `SSH`, `alias`, `device`, and raw GitHub logins on surfaces the non-technical person reads. These are the required replacements.

## D.1 Required string replacements

| Today | Required |
|---|---|
| item title `This device's GitHub SSH access` | `Your Mac's connection to GitHub` |
| adoption `detail`: `Your existing {alias} alias already works and signs in as {login}. I'll leave it exactly as it is.` | `This Mac already connects to GitHub, and I checked that it works and that it's signed in as you. I'll leave that exactly as it is and add the one connection it's still missing.` |
| `decline_detail`: `Without this, the {alias} alias won't be set up, and this device won't have everything it needs. Your existing {alias} alias is never touched either way.` | `Without this, this Mac keeps one of the two GitHub connections setup uses. Setup carries on, and I'll offer this again from the menu bar whenever you're ready.` |
| `The existing {alias} SSH alias could not confirm a GitHub login, so it was left exactly as it is.` | `This Mac's existing GitHub connection didn't confirm who it signs in as, so I left it exactly as it is.` |
| `GitHub could not confirm the signed-in account, so the existing {alias} SSH alias was left exactly as it is.` | `GitHub didn't confirm who you're signed in as, so I left this Mac's existing connection exactly as it is.` |
| `The existing {alias} SSH alias signs in as a different GitHub account ({login}), so it was left exactly as it is.` | `This Mac's existing GitHub connection signs in as a different account ({login}), so I left it exactly as it is.` |
| `The existing {alias} SSH alias does not resolve to {host}, so it was left exactly as it is.` | `This Mac's existing GitHub connection points somewhere other than GitHub, so I left it exactly as it is.` |
| `The existing {alias} SSH alias could not confirm real repository access, so it was left exactly as it is.` | `This Mac's existing GitHub connection couldn't reach your spaces on GitHub, so I left it exactly as it is.` |
| `Malformed Copilot-managed SSH config block.` | `I don't recognize how this Mac's GitHub connection is written down, so I left it exactly as it is.` |
| `Only one half of the device SSH keypair exists; setup did not replace it.` | `Part of this Mac's own GitHub key is missing, and I won't replace what's there.` |
| `Every alias this device needs already works. Nothing was changed.` | `This Mac's connections to GitHub already work. Nothing was changed.` |
| `The device SSH identity is ready.` | `This Mac has its own key for GitHub.` |
| `The device SSH identity can be completed without copying a private key.` | `This Mac can be given its own key for GitHub, without copying anything from another Mac.` |
| `GitHub could not list SSH keys for the authenticated account.` **(403 or 404)** | `Your GitHub sign-in doesn't include permission to add this Mac's key.` |
| `GitHub could not list SSH keys for the authenticated account.` **(any other failure)** | `GitHub didn't answer when I asked about this Mac's keys.` |
| `GitHub returned an unreadable SSH key response.` | `GitHub's answer about this Mac's keys wasn't something I could read.` |

Note on naming the other login: the third row deliberately keeps `({login})`. It is the one fact that lets the person recognize the situation, it is their own data, and a second forgotten account is the most common real cause.

Every replacement above is under 200 characters, single-line, and free of `{`, `}`, `<`, `>`, `Traceback`, `Error:`, `Exception`, `/Users/`, and `.py:` — so all of them pass `HoldingInfo.isPresentable` and can be framed under `What setup found:` without being suppressed.

## D.2 Contract additions

| Verb | Addition | Values | Why the app needs it |
|---|---|---|---|
| `onboard --json` | on the `device-ssh` stage, `registration: "not-permitted"` together with `result: "blocked"` and `config: "planned"` | new value alongside `registered` / `missing` / `not-checked` | Splits a missing GitHub permission (H7, the person's own fix) from a generic key-listing failure (H3, nobody's). **`registration` is already `{"type": "string", "minLength": 1}` in `onboard.schema.json`, so this needs no schema change and no version bump.** The app reads an enum token, never prose. |
| `auth grant --json` | starts the permission grant and returns `{user_code, verification_uri, device_code, interval}`; `--poll --device-code <code>` polls it; reports `unavailable` when it cannot drive the flow | (none) | H7's primary action, and the only thing that reveals `Show me how to grant it`. This is the same open seam as decision D-3-M3 (the wizard's sign-in device-flow verb); close both in one change rather than two. |

The app's gate table in `holdingInfo(forBlockedOnboard:)` gains exactly one branch:

```
case "device-ssh":
    if stage.registration == "not-permitted" { return H7 }
    if stage.config == "held" || stage.key == "incomplete" { return H4 }
    return H3
```

Read from a CLI-emitted enum token, never sniffed from a prose string, exactly as every existing H4 branch already is.

## D.3 The two app-side bugs this copy depends on

Both are in `/Volumes/Dev/Sites/COPILOT/copilot-control-tower/native/wizard.swift`. Without both fixes, State 1 renders nothing and the dead end persists in a new form.

**Bug 1 — `personalOnboardQuestion` drops the machine-scope row.**

The function currently filters on `scope == "personal"`:

```swift
static func personalOnboardQuestion(from report: EcosystemOnboardReport) -> (ask: [EcosystemInventoryItem], review: [EcosystemInventoryItem]) {
    let personal = (report.inventory ?? []).filter { $0.scope == "personal" }
    return (personal.filter { $0.reversible }, personal.filter { $0.action == "review" })
}
```

The CLI's SSH row is `scope: "machine"`, so it is silently dropped and the offer never appears. The scope filter must go:

- **Ask rows** are every inventory item with `reversible == true`, in the CLI's own order.
- **Review rows** are every inventory item with `action == "review"`, in the CLI's own order.
- Group both into the two cards by `scope`: `personal` into `Already in your GitHub account`, `machine` into `Already on this Mac`. The scope word itself never reaches the screen.

**Bug 2 — `componentId(fromPersonalInventoryId:)` returns `nil` for `device-ssh`.**

```swift
static func componentId(fromPersonalInventoryId id: String) -> String? {
    let prefix = "personal-"
    guard id.hasPrefix(prefix) else { return nil }
    return String(id.dropFirst(prefix.count))
}
```

The SSH item's id is `device-ssh`, which has no `personal-` prefix, so this returns `nil`, `includeOnboardSelections()` drops the consent, the apply writes nothing, and the offer repeats forever. The token map is:

- `personal-<component>` maps to `<component>` (`claude`, `codex`, `knowledge`, `cli`)
- **`device-ssh` maps to `ssh`**

`ssh` is the exact token `ensure_machine_ssh_identity` checks for: `consented = "ssh" in {value.strip().lower() for value in adopt_existing if value.strip()}`. `build_ecosystem_onboard_report` already forwards `adopt_existing` to `ssh_fn` at both plan (line 1255) and apply (line 1318), so no CLI plumbing is missing. Only the app's token is.

This is the single highest-risk line in the whole change, because it fails silently and looks like the CLI's fault.

## D.4 Ordering note, already correct

`performDetect` asks the question **before** the blocked-guard (`wizard.swift:909`), which is right and must stay that way. A plan that is blocked purely because an unrelated item needs review must still surface the question rather than dropping it behind Holding's review-only card. That is the old dead end, and the ordering is what prevents it.

---

# THE DECK DIFF

Context-anchored unified diff against `docs/03-design/control-tower-copy-deck.md`. Fourteen hunks plus the eyebrow sweep. New prose is unwrapped, matching §2.9's freshly-rewritten style; the surrounding hard-wrapped prose is left as it is except where a line is being replaced outright.

```diff
--- a/docs/03-design/control-tower-copy-deck.md
+++ b/docs/03-design/control-tower-copy-deck.md
@@ hunk 1 — §1.8, the Bob-lane prompt table
 | Kind | Detail line | Action label |
 |---|---|---|
 | `sign-in` | `Slack needs you to sign in again.` | `Sign in to Slack` |
 | `dirty-wip` | `You have unsaved changes in the way of an update. Nothing was touched.` | `Review your changes` |
+| `permission-needed` | `GitHub needs one more permission before this Mac can finish setting up.` | `Grant this on GitHub` |

@@ hunk 2 — §1.8, after the notices table
 | `waiting-on-it` | `Waiting on your organization to finish a bit of setup.` |
+
+**One notice carries an action** (an offer is not a fault, so it is a notice and not a prompt, the same call the projects offer made):
+
+| Kind | Message | Action label |
+|---|---|---|
+| `connection-offer` | `This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.` | `Add the connection` |

@@ hunk 3 — SURFACE 2 header
-One guided window, eight steps in the built flow (welcome, detect, choose components,
-departments, integrations, set up, verify, done), plus the first-class **holding**
-terminal. No time estimates anywhere. Step position reads as "Step N of 8", never a clock.
+One guided window, **ten** steps in the built flow, plus two first-class inline terminals that add no sidebar row and change no step number: the **holding** screen (§2.9) and the **one question first** screen (§2.2.1). No time estimates anywhere. Step position reads as `Step N of 10`, sentence case, never a clock.
+
+**Two steps have no section of their own below.** `Connect GitHub` (step 2) is the device-flow sign-in, whose strings live in §2.5.1. `Your projects` (step 7) is specified in full in `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-project-setup-spec.md`. The eyebrows in §2.2 through §2.8 below carry their correct built positions.

 Window title: `Set Up Copilot Control Tower`
 Sidebar header: `Set Up Copilot Control Tower`
 Sidebar section label: `SETUP`
-Roadmap row titles: `Welcome` · `Detect` · `Choose copilots` · `Departments` ·
-`Integrations` · `Set up` · `Verify` · `Done`
+Roadmap row titles: `Welcome` · `Connect GitHub` · `Detect` · `What you're getting` · `Departments` · `Integrations` · `Your projects` · `Set up` · `Verify` · `Done`

@@ hunk 4 — the eyebrow sweep, §2.2 through §2.8 (seven lines)
-## 2.2 Detect          — Eyebrow: `STEP 2 OF 8`   →  Eyebrow: `Step 3 of 10`
-## 2.3 Choose copilots — Eyebrow: `STEP 3 OF 8`   →  Eyebrow: `Step 4 of 10`
-## 2.4 Departments     — Eyebrow: `STEP 4 OF 8`   →  Eyebrow: `Step 5 of 10`
-## 2.5 Integrations    — Eyebrow: `STEP 5 OF 8`   →  Eyebrow: `Step 6 of 10`
-## 2.6 Set up          — Eyebrow: `STEP 6 OF 8`   →  Eyebrow: `Step 8 of 10`
-## 2.7 Verify          — Eyebrow: `STEP 7 OF 8`   →  Eyebrow: `Step 9 of 10`
-## 2.8 Done            — Eyebrow: `STEP 8 OF 8`   →  Eyebrow: `Step 10 of 10`

@@ hunk 5 — new §2.2.1, inserted after §2.2 Detect and before §2.3
+### 2.2.1 One question first (inline over Detect)
+
+Rendered the way Holding is rendered: a `StepShell` over the Detect stage, no sidebar row, no step-number change, `accent` blue and never orange, because this is an offer and not a pause. Entered when the CLI's plan carries at least one ask row. Never a Holding variant: an adoptable plan comes back `changes-required` or `applied`, never `blocked`, so it is structurally unreachable from Holding.
+
+An **ask row** is any inventory item with `reversible == true`, in the CLI's order, checkbox pre-selected. A **review row** is any item with `action == "review"`, no checkbox, trailing `Kept as is`. Rows are grouped into two cards by `scope`; neither the scope word nor the item id ever appears on screen.
+
+- Eyebrow: `ONE QUESTION FIRST`
+- Title: `Want me to include what you already have?`
+- Intro, chosen by which scopes are present:
+  - GitHub-account rows only: `Your GitHub account already has private spaces of your own, with your own content in them. I can include them so your copilots use what you already have, or leave them alone.`
+  - This-Mac rows only: `This Mac is already set up to reach GitHub, and I checked that what's here works. I can build on it, or leave it alone and set the rest up around it.`
+  - Both: `You already have some of this: spaces of your own on GitHub, and a working connection on this Mac. I can build on what's here, or leave it alone and set up the rest around it.`
+- Card 1 label (`scope: "personal"`): `Already in your GitHub account`
+- Card 2 label (`scope: "machine"`): `Already on this Mac`
+- Row title and row caption: the CLI's `title` and `detail`, verbatim (Appendix D holds the required strings)
+- Cleared-row caption, revealed under the row: the CLI's `decline_detail`, verbatim. A missing one renders no caption rather than invented copy.
+- Quiet line under the cards, always present: `Nothing you already have is changed. Setup only adds what's missing.`
+- Leading action: `Not now`
+- Primary action: `Include what I have`
+- Primary disabled hint, every row cleared: `Choose something to include, or select Not now.`
+- Re-plan progress card, after either action: `Checking what that means…`
+
+**The two ideas are held apart on purpose.** The row caption is the CLI's specific found fact ("I checked this, it works, I'm leaving it alone, one thing gets added"). The quiet line is the app's general guarantee, structurally true for every `action: "create"` + `reversible: true` row. Never merge them: the never-destroy promise must not depend on the CLI getting a sentence right.
+
+**Declining is never terminal.** `Not now` re-plans without those tokens and setup carries on to Detect. The offer survives in the menu bar as the `connection-offer` notice (§1.8). Without that row the CLI's decline sentence is a lie.

@@ hunk 6 — §2.7 Verify
-- Result (calm, not celebratory): `Everything checks out.`
+- Result (calm, not celebratory): `Everything checks out.` Permitted **only** when the completion rule in §2.10 passes. If it does not, Verify renders §2.10 instead. There is no hedged middle wording.

@@ hunk 7 — §2.9 opening paragraph
-Holding is six variants, not one screen. The variant is chosen by **who owns the fix**, never by what went wrong. Two of the six are not failures at all: H4 is invariant #3 working correctly (setup found something the person already owns and refused to overwrite it), and H5/H6 are patience. Only H2 and H3 are faults.
+Holding is seven variants, not one screen. The variant is chosen by **who owns the fix**, never by what went wrong. Three of the seven are not failures at all: H4 is invariant #3 working correctly (setup found something the person already owns and refused to overwrite it), H5/H6 are patience, and H7 is a request only the person can answer. Only H2 and H3 are faults.

@@ hunk 8 — §2.9 variant table, appended row + rationale
 | H6 | Waiting on your organization | `WAITING ON YOUR ORGANIZATION` | `Your organization has a bit left to set up` | `it-config-incomplete` neutral |
+| H7 | Something only you can do | `ONE THING ONLY YOU CAN DO` | `Setup needs one permission from you` | `signed-out` blue, glyph `key` |
+
+**Why H7 is its own variant.** Run the owner test on the other six: H1's owner may not be the person and its fix is outside the app; H2 and H3 name no owner and end in support details; H4's owner is the person but its frame is "nothing is wrong, decide about your own content"; H5 is time and H6 is the organization. None of them carries *the fix is yours, it is a real fix and not a decision, and you can do it right here*. That is H7, and it is the tone SOUL §7 already names: direct, singular, the one thing only he can do.

@@ hunk 9 — §2.9 intro-lines table
-| This Mac already has its own key | H4 | `This Mac already has a GitHub connection I didn't set up, so I left it exactly as it is.` |
+| This Mac's connection couldn't be confirmed | H4 | `This Mac already has a GitHub connection I didn't set up. I checked it, couldn't confirm it's safe to build on, and left it exactly as it is.` |
 | Settings here weren't set up by me | H4 | `I found settings on this Mac that I didn't set up, so I left them alone.` |
 | Your unsaved work is in the way | H4 | `Some of your own unsaved work is in the way of an update, so I left it alone.` |
+| GitHub hasn't been asked for a permission | H7 | `Setup gives this Mac its own key so it can reach GitHub safely. Adding that key needs a permission GitHub hasn't been asked for yet, and you're the only one who can give it.` |

@@ hunk 10 — §2.9 H4-only paragraph
-**H4 only:** the card `What I left alone` (one row per CLI review item, the CLI's own detail verbatim), the caption `Nothing was changed, moved, or removed.`, and the confirmation state after `Keep what I have`: title `Kept as it is`, intro `I left it exactly as it was. Control Tower keeps watch from the menu bar and picks this up if it ever changes.`
+**H4 only:** the card `What I left alone` (one row per CLI review item, the CLI's own detail verbatim) and the caption `Nothing was changed, moved, or removed.`. The confirmation after `Keep what I have` is **always §2.10**, never a resolved-sounding screen: H4 is reachable only from `result: "blocked"`, so the completion rule can never pass at that moment. The old `Kept as it is` confirmation is withdrawn.

@@ hunk 11 — §2.9 Actions paragraph
-**Actions.** … `Continue in the menu bar` (all six; never marks setup complete) … `Include what I already have` (H4, existing return path). On a repeat …
+**Actions.** `Try again` (primary: H2, H3, H5) · `Check again` (H1, H4, H6; nothing failed, so "try" would overstate it) · `Continue in the menu bar` (all seven; never marks setup complete) · `Show me how to install it` (primary: H1) · `Keep what I have` (primary: H4) · `Let setup manage it` (H4, only when the CLI declares consent for that gate) · `Include what I already have` (H4, existing return path) · `Grant this on GitHub` (primary: H7) · `Show me how to grant it` (H7, **only** when the CLI reports it cannot drive the grant itself). On a repeat of the identical hold, add one caption: `Still the same. Nothing changed.`

@@ hunk 12 — §2.9.1 heading
-### 2.9.1 Details for support (collapsed, on H2 / H3 / H4 / H6)
+### 2.9.1 Details for support (collapsed, on H2 / H3 / H4 / H6 / H7 / §2.10)

@@ hunk 13 — new §2.9.3 and new §2.10, inserted after §2.9.2's last line
+### 2.9.3 Granting the permission (the sheet behind H7's primary)
+
+  [full text as written in §3.5, §3.6 and §3.7 of this spec]
+
+## 2.10 I stopped, and here's what that means for you
+
+  [full text as written in §2.1 through §2.6 of this spec]

@@ hunk 14 — Appendix A, three rows; Appendix B, extended ban list; new Appendix D
 | `Your team hasn't made this available to you.` | `You are not entitled to this component.` |
+| `Here's where that leaves you.` | `Kept as it is.` (while five stages never ran) |
+| `This Mac can't reach GitHub on its own yet.` | `3 of 8 done` |
+| `Setup needs one permission from you.` | `Your token is missing the admin:public_key scope.` |

 Appendix B gains: `scope` (as a permission), `OAuth`, `SSH`, `alias`, `device` (say
 "this Mac"), `rank`, `manifest`, `package`, `tier`. And one permission:
 `key` is permitted, and is the settled word for what this Mac is given.

 Appendix D is added after Appendix C, carrying D.1 through D.4 of this spec verbatim.
```

---

# CHANGES TO EXISTING RATIFIED COPY

Three deliberate edits to strings that were already ratified. Each is flagged rather than slipped in.

1. **`Kept as it is` is withdrawn, not conditioned.** H4 is reachable only from `result: "blocked"`, so that screen's claim could never be true. Conditioning it would imply a passing case exists.
2. **The question screen's title.** The old one was 53 characters, over the 50-character rule, and its first sentence repeated the cards below it. `Want me to include what you already have?` is 41 characters and covers both scopes.
3. **`Nothing existing was changed.` becomes `Nothing you already have is changed. Setup only adds what's missing.`** The old line carried only half the promise, which is what let a never-destroy screen read as a refusal.

Plus one factual correction, not a copy change: the deck described an eight-step flow with stale `STEP N OF 8` eyebrows. The built flow is ten steps in sentence case. All seven eyebrows in §2.2 through §2.8 are swept to their correct built positions, and the two steps with no deck section of their own (`Connect GitHub`, `Your projects`) are named with pointers to where their strings actually live.

---

# IMPLEMENTATION CHECKLIST

- [ ] CLI: apply every string replacement in D.1 to `ssh_identity.py` and `onboard.py`
- [ ] CLI: split `_github_keys`' 403/404 case and emit `registration: "not-permitted"` on the `device-ssh` stage
- [ ] CLI: add the `auth grant --json` verb (same seam as D-3-M3)
- [ ] App: drop the `scope == "personal"` filter in `personalOnboardQuestion`; group by scope into two cards
- [ ] App: map `device-ssh` to the consent token `ssh` in `componentId(fromPersonalInventoryId:)` or its replacement
- [ ] App: add the second card and the three scope-aware intros to the question screen
- [ ] App: change the question screen's title and its quiet line
- [ ] App: add the H7 variant, its tint (`signed-out` blue), its glyph (`key`), and its two sheets
- [ ] App: add the H7 branch to `holdingInfo(forBlockedOnboard:)`, keyed on `registration == "not-permitted"`
- [ ] App: delete `holdingConfirmationView`'s `Kept as it is` body and replace it with the §2.10 pattern
- [ ] App: implement the completion rule as a single shared predicate, and route every terminal confirmation through it
- [ ] App: add the `connection-offer` notice and the `permission-needed` prompt to Region 6
- [ ] Test: a report with `config: "adoptable"` renders the question screen with a machine-scope card, and consent round-trips as the `ssh` token
- [ ] Test: `Keep what I have` on a blocked report renders §2.10 and never the word "kept" as a resolution
- [ ] Test: a report failing any one of the four completion-rule conditions never renders resolved language
