# Copy & Voice

> **Status: rebuilt from evidence 2026-08-02. Describes the shipping product at v0.3.2** (built 2026-08-01 from commit `e0bf0c3`, notarized arm64 DMG embedding pinned helper `cc 2.1.2`).
>
> **This is a retrofit, not an invention.** Copilot Control Tower already ships. Its voice is not a proposal — it is embodied in roughly 20,500 lines of Swift across `native/`, in strings that have survived seven signed releases and a live 16/16 ecosystem apply on ENAC. This document **extracts and codifies what those strings already do**. Every row in every table below is quoted **verbatim from the shipping source, with its file and line**. Where the shipped copy is weaker than the voice it is trying to speak, that gap is recorded in the **RECOMMENDATIONS** section at the end — clearly separated, never mixed into the tables of what ships today.

<!--
FACILITATION GUIDE — Copywriter
=================================
This document is the single source of truth for every word in this
product. The design team and implementation team use copy directly
from here — no paraphrasing, no improvising.

PREREQUISITE: UX Design and UI Design should be completed first.

CONVERSATION FLOW:
1. Define the voice character
2. Define speech patterns and language rules
3. Write key UI copy (empty states, CTAs, labels)
4. Define microcopy patterns (errors, confirmations, loading)
5. Establish banned language

QUESTIONS TO ASK:

## Round 1: Voice Character
- "If this product could talk, what would it sound like?"
- "Is it a confident expert? A helpful assistant? A quiet tool?"
- "What's the relationship between the product and the user?"
- "How much personality should the product have?"

## Round 2: Speech Patterns
- "Short sentences or long explanations?"
- "Formal or conversational?"
- "Does it use 'you' and 'your'?"
- "Technical language or plain language?"
- "How does it handle uncertainty?"

## Round 3: Key UI Copy
Walk through each major surface:
- "What does the user see in empty states?"
- "What does the user see while the system is processing?"
- "What do the primary CTAs say?"
- "What does the completion state say?"

## Round 4: Microcopy Patterns
- "How should error messages sound?"
- "How should success confirmations sound?"
- "How should loading/processing messages sound?"
- "How should 'no results' states sound?"

## Round 5: Banned Language
- "What words or phrases should never appear in this product?"
- "What jargon should be avoided?"
- "What buzzwords are off-limits?"

SYNTHESIS:
Write the voice definition, then provide actual copy strings
for key surfaces. This is specification — the implementation team
copies from here.
-->

---

## Where this voice came from, and where it is authoritative

Three artifacts hold the voice, in this order of authority:

| Rank | Artifact | Role |
|---|---|---|
| 1 | **The shipping strings in `native/*.swift`** | What users actually read at v0.3.2. Reality wins. |
| 2 | **`docs/03-design/control-tower-copy-deck.md`** | The ratified copy specification the code was built from — surface by surface, state by state. Code cites it in comments (`control-tower-copy-deck.md §1.1`, `§1.4`, `§1.7`). Where code and deck disagree, this document records **both** and names the drift. |
| 3 | **`SOUL.md` §7 (Voice & Tone)** | The character and the We Say / We Don't Say anchor the deck derives from. |

This document is the retrofit synthesis of all three. It supersedes the previous version of this file, which was written before the app existed and described a Tauri-era product with fabricated example strings.

---

## Two registers, one voice

The same underlying event reaches two different people through two separate binaries. The **voice** is constant; the **register** modulates. This is not a runtime down-level of one string — they are separate strings in separate files, because the two builds are separate apps (`Copilot Control Tower.app` versus `Copilot Control Tower Admin.app`, the latter compiled with `-D CT_ADMIN_BUILD`).

| Register | Who reads it | Where it lives | Rule |
|---|---|---|---|
| **User-facing** | The non-technical person the whole product exists for. No terminal. Did not choose this software. | `native/wizard.swift`, `native/control-tower-tray.swift`, `native/user-settings.swift`, `native/render-state.swift` | Plain language only. Names the copilot and the one thing to do. Never requires understanding the machinery. |
| **Admin-facing** | The organization owner setting the ecosystem up once. Competent, but still not necessarily an engineer. | `native/admin.swift`, `native/admin-support.swift` | May teach a concept before using it. Still refuses raw error text, still says "spaces" not "repositories", still never blames. |

The Admin register is **not** an engineering register. It is a *teaching* register. Admin's Orientation screen explains the inheritance model in one paragraph of plain English before asking for anything (`native/admin.swift:1697`), and its own vocabulary substitutes **"spaces"** for repositories throughout (`native/admin.swift:2645`, `:1793`, `native/admin-support.swift:1306`). That substitution is the single clearest evidence of the product's real linguistic discipline — and, as the **Banned Language** section shows, the User face does not consistently honor it.

---

## Voice

### Character

**A calm operator who refuses to guess.**

The character is stated in `SOUL.md` §7 as an air-traffic controller: "Spare, factual, unhurried. It states what is true and the one thing to do about it, then stops." The shipping strings bear that out, but they add something the character sketch does not capture and which the code demonstrably prioritizes above everything else: **the voice's defining move is declining to claim.**

Read the shipped strings and the same construction appears again and again — a first-person admission of a limit, followed by the safe thing that was done instead:

- `"I can't read the setup right now, so I won't guess."` (`native/render-state.swift:108`)
- `"I can't read your setup, so I've paused"` (`native/wizard.swift:710`)
- `"I found something that belongs to you, so I left it alone and stopped before changing anything."` (`native/wizard.swift:1473`)
- `"I can't confirm your setup is safe right now, so I'm holding off rather than guess."` (`native/wizard.swift:3294`)
- `"I couldn't read the result of this, so I won't guess."` (`native/admin-support.swift:1900`)
- `"I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again."` (`native/admin-support.swift:1149`)

That is the voice. Not "confident expert," not "helpful assistant" — **a witness under oath.** It reports what it saw, states plainly what it could not see, and never fills the gap. The product's central promise is an icon that cannot lie, and the copy is built to make lying grammatically awkward.

Three consequences follow, all visible in shipped strings:

1. **It speaks in the first person, and it owns the limit.** "I can't read this," never "the operation failed." The subject of a failure sentence is the app, never the user. There is no shipped string in `native/` that begins with "You entered" or "Invalid."
2. **It pairs every limit with a preservation guarantee.** Nearly every stop is followed by what was *not* touched: `"Nothing was changed, moved, or removed."` (`native/wizard.swift:6098`), `"Everything before it is still in place."` (`native/admin-support.swift:1061`), `"Nothing after this was changed."` (`native/admin-support.swift:1062`), `"Existing repositories were not overwritten."` (`native/admin-support.swift:1111`). The never-destroy invariant is not just an architectural property — it is a **sentence pattern**.
3. **Success is understated to the point of near-silence.** The healthy status sentence is four words: `"Everything is set up."` (`native/render-state.swift:133`). There is no toast, no confetti, no green reward mark on a passing layer — the code comment at `native/control-tower-tray.swift:1308-1311` explicitly refuses one: "a quiet dot when passing (never the colorful `.pass` reward mark — that would be exactly the 'green checkmark reward' the copy deck's hard rule 6 forbids)."

### Speech Patterns

Extracted from the shipped strings, not prescribed to them.

| Pattern | Rule | Shipped evidence |
|---|---|---|
| **First-person singular for the app's own acts and limits** | The app says "I" when it did something or couldn't. It says "Control Tower" when introducing itself or describing standing behavior. | `"I'll pick this up when you're back online"` (`wizard.swift:785`) vs. `"Control Tower keeps the parts that are already right…"` (`wizard.swift:4010`) |
| **Second person for the user's things** | "your organization", "your projects", "your Mac", "your own work". Ownership is always attributed. | `"Only your copilots' shared files were added. Your own work in these projects wasn't touched."` (`tray.swift:2492`) |
| **Name the specific copilot, never a blur** | The status sentence interpolates the copilot's display name. | `"\(component) needs you to sign in. Everything else is fine."` (`render-state.swift:143`); `"\(name) is waiting on setup from your organization."` (`render-state.swift:153`) |
| **Past tense for anything already handled** | Auto-acted things are reported, not asked about. | `"Your previous setup was preserved in a rollback copy."` (`wizard.swift:5752`); `"Granted. Picking up where I left off."` (`wizard.swift:6862`) |
| **Cause-then-consequence, joined by "so"** | The signature connective. The reason comes first, the safe action second. | `"Your setup is already being updated by something else, so I stepped back rather than get in the way."` (`wizard.swift:799`) |
| **The one thing to do, as a plain imperative button** | Buttons are verb phrases naming the actual act. Never "OK", never "Submit". | `"Grant this on GitHub"`, `"Review your changes"`, `"Show me how to install it"`, `"Keep what I have"`, `"Continue in the menu bar"` |
| **Sentences under ~20 words; at most two per message** | Status sentences are one sentence. Intros run to three at most, and only in the wizard where there is room. | `"Let's finish setting you up."` (`render-state.swift:147`) |
| **No em-dashes, anywhere** | A house rule stated in the file header at `native/wizard.swift:20` and honored throughout. Periods, commas, colons, parentheses only. | Enforced by convention; the shipped strings contain none. |
| **No time estimates, no percentages, no counts-as-promises** | Progress is named by phase, never by clock. | `"Connecting securely to GitHub…"`, `"Setting up…"`, `"Checking…"`. The one duration hedge is deliberately vague: `"This can take a few seconds."` (`wizard.swift:3870`) |
| **Offer an exit at every stop** | No holding screen is a dead end. Every one carries `"Continue in the menu bar"` plus a retry. | `wizard.swift:5958, 5990, 6053, 6117, 6248, 6270, 6319, 6374, 6414` |

### Voice Role

**A supervisor that reports to you.** Not an assistant that performs, not a friend that cheers, not a wizard that knows better.

The relationship is asymmetric in a specific way: the app has read access to a great deal and write authority over almost nothing the user cares about. It says so out loud. `"This app never manages people. GitHub does."` (`native/admin.swift:1757`) is the purest statement of the role — Control Tower is a *renderer of someone else's truth*, and it tells you where the truth lives so you can go check.

This is why the voice can be so plain without being condescending. It is not simplifying a hard thing for a simple person; it is reporting a verdict it did not compute. Invariant #1 ("parse, never compute") is a copy constraint as much as an architectural one: the app has no grounds to editorialize, so it doesn't.

**The essence is democratization.** The product's job is to put a technical person's superpowers in a non-technical person's hands. That means the copy carries a hard requirement most product copy does not: **the reader must never need to understand the machinery to act correctly.** A string that is accurate but requires the reader to know what a layer, a manifest, or a repository is has failed at the product's actual purpose, no matter how true it is. The welcome screen states the contract directly:

> `"You don't need to be technical for any of this. Control Tower sets everything up for you, then keeps it up to date quietly in the background. It lives as a small icon in your menu bar. When the icon is quiet, everything's ready."` — `native/wizard.swift:3759`

Every banned term in the last section is banned because it breaks that promise.

---

## Key UI Copy

Everything below is quoted **as shipped at v0.3.2**. `\(…)` marks a Swift string interpolation, reproduced so the template shape is visible.

### A. The tray status sentence — the most-read string in the product

`HeaderView.sentence`, rendered verbatim next to the worst-wins glyph. Derived by a single closed switch in `native/render-state.swift:129-162` over the ten `DoctorStatus` values, so no status can be rendered without a sentence and no sentence can be fabricated.

| CLI status | Badge (`render-state.swift:33-42`) | Shipped sentence | Source |
|---|---|---|---|
| `healthy` | `none` (no badge at all) | `Everything is set up.` | `render-state.swift:133` |
| `healthy`, with a joinable department | `none` | `Everything on this Mac is set up.` | `render-state.swift:132` |
| `setupNeeded` | `hollow` | `Let's finish setting you up.` | `render-state.swift:147` |
| `syncing` / `updatingApp` | `ring` | `Bringing everything up to date…` | `render-state.swift:136` |
| `updateAvailable` | `ring` | `An update is ready. I'll install it quietly.` | `render-state.swift:138` |
| `offline` / `waitingForNetwork` | `cloudSlash` | `You're offline. I'll pick up where I left off when you're back.` | `render-state.swift:140` |
| `signedOut` | `key` | `\(component) needs you to sign in. Everything else is fine.` | `render-state.swift:143` |
| `signedOut`, no component identified | `key` | `You need to sign in. Everything else is fine.` | `render-state.swift:145` |
| `itConfigIncomplete`, one copilot | `triangle` | `\(name) is waiting on setup from your organization.` | `render-state.swift:153` |
| `itConfigIncomplete`, several | `triangle` | `Some copilots are waiting on setup from your organization.` | `render-state.swift:151` |
| `itConfigIncomplete`, none named | `triangle` | `Your organization hasn't finished setting this up.` | `render-state.swift:155` |
| `needsAttention` | `triangle` | `\(attention.name) needs attention in your \(attention.layer).` | `render-state.swift:158` |
| `needsAttention`, nothing nameable | `triangle` | `Something needs attention.` | `render-state.swift:160` |
| **Any CLI read failure** | `bang` | `I can't read the setup right now, so I won't guess.` | `render-state.swift:108` |
| Sync in flight (overrides the above) | `ring` | `Bringing everything up to date…` | `tray.swift:1514` |

The `\(attention.layer)` slot is filled by `plainLayer()` (`render-state.swift:59-67`), which maps the machine's layer ids to plain words before they reach the sentence: `foundation` → **"core setup"**, `org` → **"organization"**, `dept`/`department` → **"department"**, `personal` → **"personal setup"**, anything else → **"setup"**. This function is the product's jargon firewall, and it is the model for how every other layer reference should behave.

Copilot display names are likewise mapped, never raw (`render-state.swift:47-55`): `claude` → **"Claude Copilot"**, `codex` → **"Codex Copilot"**, `cli` → **"CLI Copilot"**, `knowledge` → **"Knowledge Copilot"**.

### B. The tray popover

| Element | Shipped copy | Source |
|---|---|---|
| Section: component tree | `YOUR COPILOTS` | `tray.swift:1549` |
| Section: joinable departments | `AVAILABLE TO JOIN` | `tray.swift:1570` |
| Section: shared integrations | `SHARED WITH YOUR TEAM` | `tray.swift:1601` |
| Shared integrations subtitle | `Ready for you. Nothing to sign into.` | `tray.swift:1604` |
| Section: personal accounts | `YOUR ACCOUNTS` | `tray.swift:1608` |
| Layer cell labels (plain, ratified) | `Core setup` · `Your organization` · `Your department` · `This Mac` | `tray.swift:1319-1323` |
| Layer cell, no membership | `You're not in this one` | `tray.swift:1350, 1356` |
| Join row, in flight | `Joining \(entry.name)…` | `tray.swift:1424` |
| Join disabled, offline | `Waiting for the network.` | `tray.swift:1563` |
| Join disabled, syncing | `Finishing an update first.` | `tray.swift:1564` |
| GitHub account state | `Signed in` / `Needs sign-in` | `tray.swift:1593-1596` |
| Actions | `Sync now` · `What changed` · `Set up` · `Settings…` | `tray.swift:1635, 1642, 1656, 1662` |
| Offline footnote under actions | `Waiting for the network.` | `tray.swift:1670` |
| Prompt: unsaved work blocking an update | `You have unsaved changes in the way of an update. Nothing was touched.` + button `Review your changes` | `tray.swift:1698, 1701` |
| Prompt: missing GitHub permission | `GitHub needs one more permission before this Mac can finish setting up.` + button `Grant this on GitHub` | `tray.swift:1722, 1725` |
| Notice: project setup available | `Building something on this Mac? I can set your copilots up in your projects too.` | `tray.swift:1780` |
| Notice: second GitHub connection missing | `This Mac is missing one of the two GitHub connections setup uses. Nothing is added until you say so.` + button `Add the connection` | `tray.swift:1815, 1818` |
| Projects, folder chosen but empty | `No projects in that folder yet. Any new one you create will get your copilots automatically.` | `tray.swift:1860` |
| Projects, no folder chosen | `Control Tower isn't watching any folder yet. Choose the folder where you keep your projects and it will set your copilots up there.` | `tray.swift:1864` |
| Projects, reassurance | `Come back whenever you want` / `Project setup is always available here. Finish one or two projects now, or return later—unfinished routes stay under Your projects.` | `tray.swift:1937, 1939` |

### C. The right-click menu

| Item | Shipped label | Source |
|---|---|---|
| Sync | `Sync now` | `tray.swift:2660` |
| Change log | `What changed` | `tray.swift:2665` |
| Settings (⌘,) | `Settings...` | `tray.swift:2669` |
| Admin build only | `Open Administration...` | `tray.swift:2681` |
| Quit | `Quit` | `tray.swift:2687` |

### D. "What changed"

| Element | Shipped copy | Source |
|---|---|---|
| Header | `Recently` | `tray.swift:2422` |
| Empty state | `Nothing has changed since you last looked.` | `tray.swift:2468` |
| Group: newly set up | `Projects set up for you` | `tray.swift:2489` |
| Preservation note | `Only your copilots' shared files were added. Your own work in these projects wasn't touched.` | `tray.swift:2492` |
| Group: updated | `Projects brought up to date` | `tray.swift:2507` |
| Preservation note | `Only your copilots' shared files were updated. Your own work in these projects wasn't touched.` | `tray.swift:2510` |
| Per-component line | `Updated \(name) across \(updated.count) of your projects, to \(target).` | `render-state.swift:325` |
| Per-component line, mixed targets | `Updated \(name) across \(updated.count) of your projects.` | `render-state.swift:327` |
| Per-project detail | `Already up to date` · `Updated to \(lockAfter)` · `Waiting on your unsaved changes` · `Blocked` · `Offline` · `No report` | `render-state.swift:337-350` |

### E. The nine-stage wizard

Sidebar labels (`wizard.swift:70-79`): `Welcome` · `Connect GitHub` · `Detect` · `What you're getting` · `Departments` · `Your connections` · `Your projects` · `Set up` · `Verify`.

| Step | Eyebrow | Title | Intro | Source |
|---|---|---|---|---|
| 1 | `Step 1 of 9` | `Welcome to your copilots.` | `Your company just gave you a set of AI copilots to help with your everyday work. This app, Copilot Control Tower, is how they land on your Mac and how they stay current.` | `wizard.swift:3752-3754` |
| 2 | `Step 2 of 9` | `Connect GitHub` | `GitHub comes first. It's how Control Tower knows what your team shares with you, and where your own space lives. Signing in happens in your browser, on GitHub's own page. Control Tower never asks for your password.` | `wizard.swift:3808-3810` |
| 2 (inline) | `BEFORE YOU SIGN IN` | `Which organization are you with?` | — | `wizard.swift:3912-3913` |
| 3 | `Step 3 of 9` | `Checking what's already here` | `Control Tower keeps the parts that are already right, safely moves or repairs recognized earlier setup, and leaves anything unfamiliar untouched.` | `wizard.swift:4008-4010` |
| 3 (inline) | `ONE QUESTION FIRST` | `Want me to include what you already have?` | — | `wizard.swift:4298-4299` |
| 4 | `Step 4 of 9` | `Here's what you're getting` | `Everyone on your team gets all of this. There's nothing to pick. Control Tower sets it up and keeps it current for you.` | `wizard.swift:4439-4441` |
| 5 | `Step 5 of 9` | `Departments you can join` | `Joining a department brings in everything your team shares there. You can join now, or come back to this later from Settings or the menu bar.` | `wizard.swift:4483-4485` |
| 6 | `Step 6 of 9` | `Your connections` | `These are the connections Control Tower can prove are ready for you. If your organization makes another connection available, it will appear here with a working Connect button.` | `wizard.swift:4576-4578` |
| 7 | `Step 7 of 9` | `Where do you keep your projects?` | (varies by triage state) | `wizard.swift:4758-4760, 4821` |
| 8 | `Step 8 of 9` | `Setting up your copilots` (or `Some projects need another look`) | — | `wizard.swift:5530-5531` |
| 9 | `Step 9 of 9` | `Making sure everything's current` | `The only success here is everything actually being up to date.` | `wizard.swift:5715-5717` |
| 9 (done) | `Setup verified · Step 9 of 9` | `Your copilots are ready` | `Control Tower checked the setup it completed. Here is what is ready now and where to go next.` | `wizard.swift:5730-5732` |

Supporting wizard strings worth quoting for the pattern they set:

| Moment | Shipped copy | Source |
|---|---|---|
| Welcome body, the democratization promise | `You don't need to be technical for any of this. Control Tower sets everything up for you, then keeps it up to date quietly in the background. It lives as a small icon in your menu bar. When the icon is quiet, everything's ready.` | `wizard.swift:3759` |
| Welcome closer | `That's it. Have your GitHub sign-in handy and everything else is handled for you.` | `wizard.swift:3778` |
| Explaining a technical dependency in plain words | `The GitHub command line. A small tool Control Tower uses to bring in what your team shares. If it's not on this Mac, Control Tower sets it up. You'll approve it once, in your browser.` | `wizard.swift:3777` |
| Org field help | `The short name in your organization's GitHub address, like the Acme-Co in github.com/Acme-Co.` | `wizard.swift:3925` |
| Adopt-what-exists reassurance | `Nothing you already have is changed. Setup only adds what's missing.` | `wizard.swift:4332` |
| Project step, low-pressure framing | `Set up one or two projects, or continue right away. Every unfinished route stays available under Your projects in Copilot Control Tower, so you can come back later.` | `wizard.swift:4867` |
| Scope limit, stated plainly | `Control Tower looks only inside the folders listed here.` | `wizard.swift:4945` |
| Declining project setup | `Got it. I won't ask about projects again. You can turn this on any time from the menu bar.` | `wizard.swift:4950` |
| Background work, no blocking | `Also checking your other projects in the background. You don't have to wait for that.` | `wizard.swift:5570` |
| The one place the tray glyph is taught | `Control Tower now lives in your menu bar. Look for the aviators: a quiet icon means there is nothing you need to do. If something needs you, Control Tower will show a small status badge and explain the next step.` | `wizard.swift:5779` |
| Final CTA | `Finish setup` | `wizard.swift:5791` |

**Stage outcome lines** — one true sentence and one false sentence per setup stage, so the same stage can never be described two ways (`wizard.swift:1974-1976`):

- `Your organization's shared setup came through.` / `Your organization's shared setup hasn't come through.`
- `This Mac can reach GitHub on its own.` / `This Mac can't reach GitHub on its own yet.`

### F. The holding family (H1–H7) — the honest terminal

The wizard's defining structure. Seven named holding variants, each with an eyebrow that classifies the stop, a title in the app's own voice, and an intro that pairs the limit with a preservation guarantee. `HoldingVariant` at `wizard.swift:465-473`; copy at `wizard.swift:694-870`.

| ID | Eyebrow | Title | Intro | Source |
|---|---|---|---|---|
| H1 | `ONE MORE PIECE TO INSTALL` | `The setup helper isn't installed yet` | `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.` | `wizard.swift:694-696` |
| H2 | `SETUP PAUSED` | `I can't read your setup, so I've paused` | (varies by reason — see below) | `wizard.swift:709-710` |
| H3 | `SETUP PAUSED` | `I couldn't finish one part of setup` | (the CLI's own stage detail) | `wizard.swift:722, 736` |
| H4 | `ONE THING TO DECIDE` | `Something here is already yours` | (varies by what was found) | `wizard.swift:766-767` |
| H5 | `WAITING FOR THE NETWORK` | `I'll pick this up when you're back online` | `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` | `wizard.swift:784-786` |
| H5b | `WAITING FOR THE NETWORK` | `Something else is updating right now` | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` | `wizard.swift:797-799` |
| H6 | `WAITING ON YOUR ORGANIZATION` | `Your organization has a bit left to set up` | — | `wizard.swift:812-813` |
| H7 | `ONE THING ONLY YOU CAN DO` | `Setup needs one permission from you` | `Setup gives this Mac its own key so it can reach GitHub safely. Adding that key needs a permission GitHub hasn't been asked for yet, and you're the only one who can give it.` | `wizard.swift:827-829` |

**H2 by underlying reason** (`wizard.swift:3286-3342`) — note that the machine reason token itself is never displayed, only its plain-language consequence:

| Underlying failure | Shipped sentence |
|---|---|
| Helper present but wouldn't start | `The setup helper is on this Mac, but it wouldn't start just now, so I won't guess.` |
| Can't read local state | `I can't read what's already on this Mac right now, so I won't guess.` |
| Version mismatch | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` |
| Missing security field (fails closed) | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` |
| Couldn't read the org from GitHub | `I couldn't read your organization's setup from GitHub, so I've paused.` |
| Verb the helper doesn't offer | `Control Tower asked your setup for something it doesn't offer. An update should line them back up.` |
| Anything else | `Something stopped me from reading your setup, so I won't guess.` |

**The honest-incomplete screen** — shown when verification does not prove completion, deliberately replacing the celebratory Done screen (`wizard.swift:6171-6248`):

| Element | Shipped copy |
|---|---|
| Eyebrow | `SETUP ISN'T FINISHED` |
| Title | `Here's where that leaves you` |
| Nothing-happened state | `Nothing yet. Setup stopped before anything was put in place.` |
| Preservation guarantee | `Nothing you already had was changed, moved, or removed.` |
| Actions | `Try again` · `Include what I already have` · `Continue in the menu bar` |

**Holding actions**, the closed set: `Try again` · `Check again` · `Continue in the menu bar` · `Keep what I have` · `Include what I already have` · `Use a different organization` · `Show me how to install it` · `Show me the command` · `Show me how to grant it` · `Grant this on GitHub`.

**Repeat-hold acknowledgement** (shown only from the second consecutive identical hold): `Still the same. Nothing changed.` (`wizard.swift:6440`)

### G. Handoff sheets — where the copy hands a technical step to a technical person

The product's answer to "what if the one remaining step genuinely requires a terminal": it does not hide the command, and it does not assume the reader can run it. Each sheet offers the same fork.

| Sheet | Title | Body | Source |
|---|---|---|---|
| Install the helper | `Installing the setup helper` | `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.` | `wizard.swift:6724, 6728` |
| Grant the permission | `Grant the permission` | `GitHub will ask you to confirm this. Copy the code below, open the page, and paste it in.` | `wizard.swift:6812, 6815` |
| Grant by hand | `Granting the permission by hand` | `This is one command. If you're comfortable in Terminal, paste it there. If you're not, copy it and send it to whoever looks after your Mac.` | `wizard.swift:6908, 6912` |
| Org sign-in ID | `Giving this Mac your organization's sign-in ID` | `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. It only tells this Mac the ID your organization's sign-in already has; it changes nothing else.` | `wizard.swift:6954, 6958` |
| Find the org name | `Finding your organization's name` | `It's on the page you downloaded Control Tower from, and in the email that sent you there. If you can't find either, send this to whoever looks after your Mac.` | `wizard.swift:7000, 7004` |

The recurring phrase **"whoever looks after your Mac"** is the product's plain-language substitute for "IT" or "your administrator." It appears at `wizard.swift:6302, 6912, 6958, 7004`. It is doing real work: it names a role without assuming an org chart, and it works for a five-person company and a five-thousand-person one.

### H. Project triage — five CLI-authored categories

`ProjectTriageCategory` at `wizard.swift:170-199`. The category never classifies anything; it filters rows the CLI already classified. The copy reflects that: each title names the *actor*, not the *fault*.

| Category | Title | Short meaning |
|---|---|---|
| `ready` | `Ready` | `No action needed` |
| `safeFinish` | `Can finish automatically` | `Review the exact additions first` |
| `guidedSetup` | `Needs guided setup` | `A coding assistant can complete these` |
| `ownerDecision` | `Needs the project owner` | `A named decision is required` |
| `couldNotConfirm` | `Couldn't confirm` | `Review what could not be proven` |

Terminal-launch outcomes (`wizard.swift:2652-2686`) keep the same shape — what happened, what was preserved, what to do:

- `\(assistant.displayName) is running in Terminal. Watch it there or continue setup; Control Tower will verify the project when you return.`
- `\(assistant.displayName) isn't available in Terminal. The guided prompt was copied, and nothing in the project was changed.`
- `Control Tower needs permission to run guided setup in Terminal. Allow Terminal under System Settings → Privacy & Security → Automation, then try again. The prompt was copied, and nothing was changed.`
- `\(assistant.displayName) is diagnosing in read-only mode in Terminal. Nothing may change in the project; Control Tower will check the project when you return.`

### I. Settings

| Element | Shipped copy | Source |
|---|---|---|
| Window heading | `Your setup` | `user-settings.swift:476, 482, 497` |
| Component names | `Knowledge Copilot` · `CLI Copilot` · `Claude Copilot` · `Codex Copilot` | `user-settings.swift:32-35` |
| Tier labels | `Foundation` · `Organization` · `Department` · `Personal` | `user-settings.swift:361-364` |
| Tier states | `Ready` · `Needs review` · `Needs attention` · `Needs setup` · `Could not check` · `Local work preserved` · `Found, not verified` · `Needs creation` · `Needs download` · `Needs initialization` · `Needs update` | `user-settings.swift:173-187, 250-278, 306-352` |
| Component overall | `Ready` / `Needs setup` | `user-settings.swift:199` |
| Personal explained | `Stored in \(row.owner)/\(row.name), a private GitHub repository only you can access.` | `user-settings.swift:302` |
| GitHub, signed in | `Signed in as \(auth.identity?.login ?? "your GitHub account").` | `user-settings.swift:670` |
| GitHub, signed out | `This Mac is not signed in to GitHub.` | `user-settings.swift:672` |
| Connections, none | `No additional organization connections are available in Control Tower right now.` | `user-settings.swift:716` |
| Projects, no folder | `No projects folder is selected. Control Tower is not watching any folder.` | `user-settings.swift:810` |
| Projects, declined | `You chose not to use project setup on this Mac. You can return whenever you want.` | `user-settings.swift:816` |
| Projects, none found | `No projects were found in the selected folder.` | `user-settings.swift:822` |
| Return invitation | `Come back whenever you want` / `Finish one or two projects now, or return later. Every unfinished route stays available under Your projects.` | `user-settings.swift:869, 871` |

### J. Admin — the 16 surfaces

Sidebar labels, onboarding (`admin.swift:546-558`): `Orientation` · `Prerequisites` · `Contacts` · `Connect GitHub` · `Describe your organization` · `Integrations` · `Secret store` · `Review setup` · `Organization setup` · `Setup check` · `Done`.

Sidebar labels, governance (`admin.swift:584-592`): `Add a department` · `Someone left` · `Connect the shared store` · `Org setup` · `Analytics`.

| Surface | Title | Key copy | Source |
|---|---|---|---|
| Orientation | `Here's what you're building, and the whole path` | `Your copilots live in a set of shared spaces on GitHub that build on one another. The open-source foundation sits at the bottom. Your organization adds its own on top. Each department adds what only it needs. Each person adds their own on top of that. Everyone inherits everything beneath them, so you share broad capabilities widely and keep specialized ones narrow.` | `admin.swift:1696-1697` |
| Orientation, the adoption promise | — | `Admin checks GitHub first, adopts what is already safe, creates only confirmed-missing private spaces, and stops for review instead of overwriting unfamiliar content. Nobody has to delete an existing setup to use this app.` | `admin.swift:1710` |
| Prerequisites | `Before you begin` | `Admin includes the local tools it needs and checks them for you. You only provide organization decisions and approve GitHub access.` | `admin.swift:1847-1848` |
| Contacts | `Who's who` | `Record who owns this setup, so the handoff is never guesswork. These names show in the handoff banner and in the setup check.` | `admin.swift:1896-1897` |
| Connect GitHub | `Get this Mac ready` | `Admin includes the local tools it needs. It checks GitHub access and your organization automatically, then asks only for approvals GitHub requires from you.` | `admin.swift:1933-1934` |
| Describe your organization | `Describe your organization` | `Tell setup your organization's name, the development harnesses it uses, and its departments. As you type, you'll see exactly what will be created. Nothing is created here. This is the plan setup will follow.` | `admin.swift:2139-2140` |
| Integrations | `Integrations` | `An integration here is a small command-line tool a developer builds, so a copilot can reach a system like Salesforce or your calendar. It isn't something you switch on.` | `admin.swift:2307-2308` |
| Integrations, honest empty | — | `There's nothing to set up here today. No integrations exist yet, and that's expected. They arrive when your departments' engineers build and publish them.` | `admin.swift:2342` |
| Secret store | `Your shared secret store` | `A shared secret store is one service that holds your organization's keys and hands them out by team. Shared integrations need it: an integration names the key it needs, and at runtime the store checks that the person is on the right GitHub team and only then hands over the key. That is why a key never lives in a repo or in this app.` | `admin.swift:2393-2394` |
| Secret store, no store yet | `No store yet?` | `Shared integrations can't work until you connect a store. You have no integrations yet, so you can finish setting up now and connect a store before your first one is built.` | `admin.swift:2488, 2490` |
| Someone left | — | `People join a department by being added to its team on GitHub. Add someone to the \(first.name) team and they can join \(first.name) from their own copilot. This app never manages people. GitHub does.` | `admin.swift:1757` |
| Done | — | `Your team installs Copilot Control Tower themselves. The setup check above only confirmed your organization's spaces on GitHub, not any one person's Mac, so the first person who signs in is the real test of that.` | `admin-support.swift:1730` |

**Admin run-checklist states** (`admin-support.swift:1058-1064`), the clearest error-recovery grammar in the codebase:

| State | Shipped copy |
|---|---|
| Not started | `Not started yet.` |
| Working | `Working on it now.` |
| Slow | `Still working on this one. GitHub can be slow to answer.` |
| Failed | `Couldn't finish this one. Everything before it is still in place. \(detail)` |
| Refused | `Setup stopped here on purpose. Nothing after this was changed. \(detail)` |
| No answer | `No answer yet.` |
| Never reported | `Setup didn't say what happened here.` |
| Long silence | `Setup hasn't reported anything for a while. Nothing has been undone, and nothing is lost.` |

**The secret-detection guard** (`admin.swift:428`), a rare piece of copy that teaches the security model at the exact moment it matters: `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.`

---

## Microcopy Patterns

### Errors

**The shipped structure is three parts, not two:** *[what I could not do] + [what I did instead / what is untouched] + [the one thing to try]*. The middle clause — the preservation guarantee — is what distinguishes this product's error voice from generic error copy, and it appears in nearly every shipped failure string.

| Condition | Shipped copy | Source |
|---|---|---|
| CLI unreadable, any reason | `I can't read the setup right now, so I won't guess.` | `render-state.swift:108` |
| Version mismatch | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` | `wizard.swift:3290` |
| Security field missing (fails closed) | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` | `wizard.swift:3294` |
| Helper missing | `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.` | `wizard.swift:696` |
| Helper won't start | `Something on this Mac stopped the setup helper, so I've paused.` | `wizard.swift:3334` |
| Network unreachable | `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` | `wizard.swift:786` |
| Something else holds the lock | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` | `wizard.swift:799` |
| Found the user's own work | `I found something that belongs to you, so I left it alone and stopped before changing anything.` | `wizard.swift:1473` |
| Unfamiliar local settings | `I found settings on this Mac that I didn't set up, so I left them alone.` | `wizard.swift:2264` |
| Pre-existing GitHub connection | `This Mac already has a GitHub connection I didn't set up. I checked it, couldn't confirm it's safe to build on, and left it exactly as it is.` | `wizard.swift:2221` |
| Unsaved work blocks an update | `Some of your own unsaved work is in the way of an update, so I left it alone.` | `wizard.swift:2302` |
| Org name looks like an email | `That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.` | `wizard.swift:3990` |
| Org name has bad characters | `Names on GitHub use letters, numbers, and single dashes, and nothing else.` | `wizard.swift:3996` |
| Admin: GitHub timed out | `GitHub didn't respond in time, so setup stopped safely. Existing repositories were not overwritten. Check your connection and try again.` | `admin-support.swift:1111` |
| Admin: couldn't write the plan | `I couldn't write the setup file, so I won't hand off a command that points at nothing. Try again.` | `admin-support.swift:1149` |
| Admin: couldn't read a result | `I couldn't read the result of this, so I won't guess.` | `admin-support.swift:1900` |
| Admin: a secret was pasted | `That looks like a secret. This setting never holds secrets. Secrets live in the store itself, or in your keychain, never here.` | `admin.swift:428` |
| Settings: report unreadable | `Control Tower couldn't check whether the ecosystem is complete.` + `Nothing was changed, and Control Tower will not call the ecosystem ready without that report.` | `user-settings.swift:484, 486` |

**Never done in an error, verified absent from `native/`:** no error codes shown to the user; no raw `stderr` (`cli-client.swift` never reads it at all — see the note at `render-state.swift:424`); no "contact support"; no all-caps alarm words; no blame construction; no exclamation marks on a failure.

### Success States

**Understatement is the rule, and silence is the default.** The healthy tray state renders **no badge at all** (`render-state.swift:35`: `case .healthy: return .none`) and a four-word sentence. A passing layer gets a grey dot, explicitly not a green checkmark (`tray.swift:1308-1311`).

| Moment | Shipped copy | Source |
|---|---|---|
| Steady state, everything current | `Everything is set up.` | `render-state.swift:133` |
| A copilot verified | `Ready` | `tray.swift:1373`, `user-settings.swift:177` |
| Wizard completion | `Your copilots are ready` | `wizard.swift:5731` |
| Wizard completion, the standard it met | `The only success here is everything actually being up to date.` | `wizard.swift:5717` |
| Project verified | `Project setup preserved and verified.` | `wizard.swift:5500` |
| Permission granted | `Granted. Picking up where I left off.` | `wizard.swift:6862` |
| Rollback protected the user | `Your previous setup was preserved in a rollback copy.` | `wizard.swift:5752` |
| Contact saved | `Saved.` | `admin.swift:1909` |
| Admin readiness met | `Everything required on this Mac and GitHub is ready.` | `admin.swift:2030` |
| Admin setup check clean | `Everything is set up and verified.` | `admin-support.swift:1445` |
| Store connected | `Connected. This will be included when you hand off.` | `admin.swift:2481` |

There is no confetti, no emoji, no exclamation mark, and no "Congratulations" anywhere in `native/`. The strongest celebratory word in the entire product is **"Ready."**

### Loading & Processing

Phase names only. No percentages, no counts presented as promises, no time remaining. The one duration reference in the whole User face is deliberately non-committal.

| Moment | Shipped copy | Source |
|---|---|---|
| Device flow starting | `Connecting securely to GitHub…` | `wizard.swift:3867` |
| Device flow, the only duration hedge | `This can take a few seconds.` | `wizard.swift:3870` |
| Waiting on the browser | `Waiting for you to finish in your browser…` | `wizard.swift:3839, 6843` |
| Joining a department | `Joining…` / `Joining \(entry.name)…` | `wizard.swift:4541`, `tray.swift:1424` |
| Checking connections | `Checking your organization's connections…` | `wizard.swift:4705` |
| Checking selected folders | `Checking only the folders you selected…` | `wizard.swift:4764` |
| Checking projects | `Control Tower is checking Claude and Codex setup. You can continue when the results are ready.` | `wizard.swift:4769` |
| Applying setup | `Setting up…` | `wizard.swift:5590`, `admin.swift:2613` |
| Verifying | `Checking…` | `wizard.swift:5723` |
| Background work, explicitly non-blocking | `Also checking your other projects in the background. You don't have to wait for that.` | `wizard.swift:5570` |
| Syncing (tray) | `Bringing everything up to date…` | `tray.swift:1514` |
| Admin, slow call | `Still working on this one. GitHub can be slow to answer.` | `admin-support.swift:1022` |
| Admin, unusual delay | `Still writing your setup file. That's unusual for a file on this Mac.` | `admin-support.swift:1192` |
| Admin, read-only reassurance | `Checking what's really on GitHub. This only reads, it changes nothing.` | `admin-support.swift:1611` |
| Admin, read-only reassurance | `Checking your \(preview.count) spaces on GitHub. Nothing is being changed.` | `admin-support.swift:1306` |

Note the pattern in the last three: while the app is working, it says **what it will not do**. Waiting is when a non-technical user's anxiety peaks, and the copy answers the unasked question ("is it breaking something right now?") before it is asked.

### Empty States

**The shipped structure is three parts:** *[what is here] + [why it is empty, without fault] + [what will change it]*. Critically, the "why" clause is almost always **not the user's doing** — emptiness is framed as a normal, expected, forward-looking condition.

| Surface | Shipped copy | Source |
|---|---|---|
| No departments available | `No departments are available to you yet. When someone adds you to one, it'll show up here.` | `wizard.swift:4488` |
| No connections available | `No additional organization connections are available in Control Tower right now.` | `wizard.swift:4721, 4739`, `user-settings.swift:716` |
| No folder chosen | `No folder chosen yet. Nothing is being watched.` | `wizard.swift:4885` |
| Folder chosen, nothing in it | `Control Tower checked the folders above and did not find projects with Claude or Codex setup. Choose another folder, or continue setup and add one later.` | `wizard.swift:4963` |
| Watched folder, no projects | `No projects in that folder yet. Any new one you create will get your copilots automatically.` | `tray.swift:1860` |
| No folder watched (tray) | `Control Tower isn't watching any folder yet. Choose the folder where you keep your projects and it will set your copilots up there.` | `tray.swift:1864` |
| Search returned nothing | `No projects in this category match “\(projectSearchText)”.` | `wizard.swift:5122` |
| Nothing changed | `Nothing has changed since you last looked.` | `tray.swift:2468` |
| Nothing was set up | `Nothing yet. Setup stopped before anything was put in place.` | `wizard.swift:6188` |
| No requirement reported | `No missing requirement was reported.` | `wizard.swift:5405`, `tray.swift:2209` |
| Admin: no integrations exist | `There's nothing to set up here today. No integrations exist yet, and that's expected. They arrive when your departments' engineers build and publish them.` | `admin.swift:2342` |
| Admin: no departments | `No departments are set up yet.` | `admin-support.swift:1776` |
| Admin: nothing published | `None published yet.` | `admin-support.swift:2028` |
| Admin: no plan yet | `Type your organization's name to see the plan.` | `admin.swift:2290` |
| Admin: nothing to describe yet | `Describe your organization first, so there's something here to read.` | `admin-support.swift:2012` |

`and that's expected` in the Admin integrations empty state is the single best empty-state clause in the product — it converts an absence into a normal stage of a process.

---

## Banned Language

**The rule this section enforces:** the product's essence is democratization — a technical person's superpowers in a non-technical person's hands. A word is banned when reading it correctly requires understanding the machinery. Accuracy is not a defense. A string that is perfectly true and forces the reader to learn what a *layer* or a *manifest* is has already failed at the job the product exists to do.

The list below is the ratified ban from `docs/03-design/control-tower-copy-deck.md` Appendix B, extended with the terms this survey found leaking in the shipping code.

### The stop list

| Banned | Register scope | Why | Say instead (shipped precedent) |
|---|---|---|---|
| **`layer`** (as a user-facing noun), `tier`, `overlay`, `rank` | User face — banned. Admin — banned as bare vocabulary; teach the *relationship* instead. | The inheritance model is the machinery. A person needs to know what is theirs and what is shared, never how many strata the resolver walks. Admin's Orientation teaches the concept in plain sentences without ever using the word (`admin.swift:1697`). | `Core setup` · `Your organization` · `Your department` · `This Mac` (`tray.swift:1319-1323`); `core setup` / `organization` / `department` / `personal setup` in prose (`render-state.swift:59-67`) |
| **`manifest`**, `package`, `schema`, `schema major`, `flock`, `lock` | Everywhere | Pure contract vocabulary. `schema_version` is the app's fail-closed gate (`cli-client.swift:313-361`); the *number* must never surface. The user gets the consequence, not the mechanism. | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` (`wizard.swift:3290`) |
| **`repository`**, `repo`, `checkout`, `clone`, `mirror`, `origin`, `remote` | User face — banned. Admin uses **`spaces`**. | "Repository" requires knowing Git exists. Admin already proved the substitution works at scale: `Org spaces: … Private.` (`admin.swift:2645`), `\(count) private spaces` (`admin-support.swift:1793`). | `spaces` · `your team's shared space` · `Your organization's setup file` |
| **`git`**, `commit`, `SHA`, `diverged`, `merge`, `fast-forward`, `HEAD`, `pinned version`, `branch` | User face — banned outright. | This is the deepest machinery in the product and the least translatable. Telling a non-technical person to "resolve it in Git" is a dead end wearing an instruction's clothes. | Name the *consequence* and the *actor*: `Something here is already yours` (`wizard.swift:767`); `Whoever looks after your Mac can pick this up from here.` (`wizard.swift:6302`) |
| **`ecosystem`**, `topology`, `inventory`, `roster`, `evidence-backed` | User face — banned. Admin — allowed once taught (`Learn how the ecosystem works ›`, `admin.swift:1719`). | Internal architecture nouns. The user has copilots, not an ecosystem. | `your copilots` · `your setup` · `what you're getting` |
| **`entitled`**, `entitlement`, `provision`, `materialize`, `resolve`, `fan-out`, `verb`, `parse` | Everywhere on a user surface | Verb and state names from the CLI contract. `materialize` is literally a `WizardStage` case name; its user-facing title is correctly `Set up` (`wizard.swift:76`). Keep it that way. | `Set up` · `You're not in this one` (`tray.swift:1356`) · `Your team hasn't made this available to you.` |
| **`token`**, `scope`, `OAuth`, `SSH`, `device flow`, `client ID` | User face — banned. Admin — allowed only where GitHub itself uses the term and the field demands it (`admin.swift:1956, 1981`). | Credential mechanics. The one settled exception is **`key`**, which the deck explicitly permits and the code uses well. | `Setup needs one permission from you` (`wizard.swift:828`); `Setup gives this Mac its own key so it can reach GitHub safely.` (`wizard.swift:829`) |
| **`daemon`**, `process`, `exit code`, `stderr`, `JSON`, `YAML`, `payload`, `DTO` | Everywhere | Implementation surface. The app never reads `stderr` by construction; it must never print one either. | (state the consequence) |
| **`MDM`**, `.mobileconfig`, `profile key`, `forced configuration` | Everywhere | MDM was dropped as a mechanism entirely (`cse-alignment-decisions.md` D4). The words must not outlive the feature. | — |
| **`device`** as a noun for the user's computer | Everywhere | `this Mac` is the product's settled word and it appears in dozens of shipped strings. | `this Mac` |
| **`product`** meaning a copilot; **`component`** as a section label | User face | `product` is the CLI's field name and means a built output elsewhere in the ecosystem. `component` is fine in prose, never as a headline. | `YOUR COPILOTS` (`tray.swift:1549`); `Claude Copilot`, `Knowledge Copilot` |
| **`Aviator`** as a product or feature name | Everywhere as a name. **Permitted** only as a description of the glyph shape. | Dead engineering codename. The shipped string `Look for the aviators` (`wizard.swift:5779`) describes the sunglasses mark, which is the ratified brand icon — that usage is in scope. The product's name is **Copilot Control Tower**. | `Copilot Control Tower` / `Control Tower` |
| **`Healthy`**, `All good`, `Everything's fine`, any blanket claim | Everywhere | The core promise is an icon that cannot lie. A blanket reassurance is precisely the false-healthy the product exists to prevent. Note the shipped healthy sentence is `Everything is set up.` — a statement about *setup*, which the CLI proved, not about *health*, which it did not. | `Everything is set up.` |
| **`CRITICAL`**, `FATAL`, `DANGER`, `URGENT`, `❌`, all-caps alarms, red-alert framing | Everywhere | Alarm burns the credibility of the one message that matters. Every shipped failure is a calm sentence. | `SETUP PAUSED` (an eyebrow, not a shout) |
| **`Congratulations`**, `🎉`, `Awesome`, `You're all set`, `Great job`, streaks, gamification | Everywhere | Understatement is the brand. Zero emoji ship in `native/`. | `Your copilots are ready` |
| **Time estimates and progress percentages** — `about 2 minutes`, `~30 seconds`, `3 of 8 done`, countdowns | Everywhere | A false promise about a network-bound operation is a lie the user can time. Progress is named by phase. | `Setting up…` · `Still working on this one. GitHub can be slow to answer.` |
| **`Something needs your attention`**, `One or more issues`, any blended verdict | Everywhere | Must name the specific copilot. A blur is a design failure. Note `Something needs attention.` (`render-state.swift:160`) is the *last-resort* branch, reached only when the CLI named nothing — and even then it is honest rather than vague-by-choice. | `Codex Copilot needs you to sign in. Everything else is fine.` |
| **`The AI decided / determined / knows / figured out`**, `auto-resolved`, `smart`, `second brain` | Everywhere | The app parses; it never computes a verdict (invariant #1). Claiming judgment is both a lie and a brand violation. | `I won't guess.` · `Control Tower checked the setup it completed.` |
| **`Force`**, `Skip verification`, `Override`, `Make it healthy anyway`, `Unstick it` | Everywhere | No bypass affordance exists (invariant #4). The vocabulary for one must not exist either. | — |
| **`You entered the wrong…`**, `Invalid`, `Illegal`, any blame construction | Everywhere | Never blame the user. State the condition and the fix. | `That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.` |
| **`Contact support`**, `call IT`, `run doctor in a terminal`, `open Terminal` as a bare instruction | User face | The user has no terminal and no support desk. Where a command is genuinely unavoidable, the product hands it off with a script for delegating it. | `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.` (`wizard.swift:6728`) |
| **Em-dashes** | Everywhere | House rule, stated at `wizard.swift:20`. | Periods, commas, colons, parentheses |

### Jargon leaks found in the shipping copy at v0.3.2

These are real violations in the shipping app, found by reading the source. **Per the retrofit constraints they are documented here, not fixed.** No source file was modified.

| # | Leak | Shipped string | Source | Why it breaks the promise |
|---|---|---|---|---|
| **1** | **Raw layer ids and raw contract enum values printed under every copilot name in the tray popover** — the worst leak in the product | `Text(component.layers.map { "\($0.layer.label): \($0.severity.rawValue)" }.joined(separator: " · "))` — renders as `foundation: pass · organization: warn · department: pass · personal: pass` | `control-tower-tray.swift:1375` | This is on **`YOUR COPILOTS`**, the most-read region of the most-read surface. It prints the machine's own layer identifiers *and* the CLI's raw severity enum (`pass`/`warn`/`fail`) verbatim. The same file, **56 lines earlier**, already holds the ratified plain mapping (`Core setup` / `Your organization` / `Your department` / `This Mac`, `tray.swift:1319-1323`) — the row's summary line simply bypasses it. A non-technical reader is asked to decode four architecture terms and a severity taxonomy to learn something the plain labels already say. |
| **2** | Same construction, repeated on the wizard's final Verify screen | `"\(verdict) · \(layers)"`, where `layers` is the same `layer.label: severity.rawValue` join | `wizard.swift:5868-5875` | Reaches the reader at the *most* celebratory moment in the product — the "Your copilots are ready" screen — and immediately hands them `Ready · foundation: pass · organization: pass`. |
| **3** | `inherited layers` in a progress line | `Checking this Mac and its inherited layers…` | `wizard.swift:5868` | Two banned terms in a five-word progress line, on a first-run screen, to a person who has been told they do not need to be technical. |
| **4** | VoiceOver reads the raw severity token | `.accessibilityLabel("\(component.component), \(component.worstSeverity.rawValue)")` → spoken as *"Claude Copilot, warn"* | `control-tower-tray.swift:1387` | A screen-reader user hears the contract enum where a sighted user at least sees a badge shape. `LayerDot` (`tray.swift:1358`) has the same fallback. |
| **5** | `repository` and `layer` in a Settings loading line | `Checking every Copilot repository and layer…` | `user-settings.swift:478` | Two banned terms in one loading string, on the User face. |
| **6** | `repository` throughout the Settings and Detect repository-root cards | `Copilot repository folder` · `New Copilot repositories are created or downloaded here, beside the ones you already have.` · `Personal is yours; its repository is private, but its checkout stays visible in your Copilot repository folder.` | `user-settings.swift:533, 538, 550`; `wizard.swift:4086, 4095` | `checkout` is worse than `repository` — it is Git-internal. Admin already solved this exact problem with **"spaces"**; the User face did not inherit the solution. |
| **7** | `evidence-backed layers` plus raw layer names in Settings | `Each Copilot shows Foundation, Organization, your joined Department, and Personal as separate evidence-backed layers.` | `user-settings.swift:546` | Exactly the sentence the copy deck's Appendix C-4 says the user never sees. |
| **8** | `expected layers` and a raw count in the Detect summary | `\(total) expected layers across four copilots. \(visible) are visible now; \(changes) need a setup action.` | `wizard.swift:4082` | Three problems at once: the banned noun, an internal state word (`visible`), and a hardcoded `four copilots` that will be wrong the moment a fifth component exists. |
| **9** | `repository inventory` as a waiting state | `Control Tower is waiting for a complete repository inventory.` | `wizard.swift:4081` | Two banned nouns in a seven-word sentence. |
| **10** | `layer` inside the Detect promise | `Nothing is called Ready until every expected layer is visible, connected, synchronized, and verified.` | `wizard.swift:4045` | The sentence's *intent* — a strict definition of Ready — is exactly right and worth keeping. Only the vocabulary fails. |
| **11** | Git history vocabulary surfaced to the user | `\(name)'s history has diverged from the pinned version, and the content is different` · `\(name) couldn't be read as a Git repository` · `\(name) is connected to a different GitHub repository than expected` · `\(name) has local work the pinned version doesn't include` | `wizard.swift:2344-2356` | The eight-state history classifier (ADR-006) is genuinely hard, and these strings do describe it accurately. But `diverged`, `pinned version`, and `Git repository` are all machinery the reader is not equipped to act on. |
| **12** | A raw terminal instruction to a non-technical user | `\(repositoryPhrase). Resolve it in Git, then run setup again.` | `wizard.swift:2254` | The one shipped string that tells the user to go use Git. It has no delegation fork, unlike every handoff sheet in §G. |
| **13** | `CLI-generated plan` in a project triage intro | `This project has its own instructions or tools. Run the CLI-generated plan in a visible Terminal session, then Control Tower will verify the result independently.` | `wizard.swift:4832` | `CLI-generated` names the producer, which the reader does not need and cannot use. |
| **14** | Raw file paths and machine command lines shown as evidence | `"\(evidence.path): \(evidence.detail)"` · `Text(verification.command.joined(separator: " "))` · `Stop if: \(allStopConditions.joined(separator: " · "))` | `wizard.swift:5421, 5479, 5484`; `tray.swift:2225, 2318` | These live in a "Verified evidence" disclosure, which is a defensible place for detail. But `Stop if:` is an engineering conditional, not English. |
| **15** | `ecosystem` on the User face | `Control Tower couldn't check whether the ecosystem is complete.` · `Nothing was changed, and Control Tower will not call the ecosystem ready without that report.` | `user-settings.swift:484, 486` | Admin earns the word by teaching it first. Settings uses it cold. |
| **16** | The raw machine hostname where the deck specified `This Mac` | `Text(host)` renders `DoctorReport.host` verbatim as the popover's secondary line | `control-tower-tray.swift:1533-1536` | `doctor.schema.json` defines `host` as "Host identifier the verdict was computed for" — a machine name, not a phrase. The copy deck §1.1 specifies the secondary line as `This Mac` for every state. |
| **17** | Inconsistent ellipsis characters in action labels | Menu item `Settings...` (three periods, `tray.swift:2669`) versus popover button `Settings…` (single ellipsis, `tray.swift:1662`); same split at `Open Administration...` | `tray.swift:1662, 2669, 2681` | Cosmetic, but it is the same word rendered two ways on two surfaces of one app. |

### The structural finding: the ban cannot be enforced inside the app

Invariant #1 requires Control Tower to **render the CLI's verdict, not compute its own**. In practice that means the app passes **CLI-authored prose straight through to the user** in several places:

- `LayerView.detail` → the tooltip and the component-tree detail line (`tray.swift:1352, 1379`)
- `UserSettingsTierStatus.detail` ← `row.detail`, `row.packageDetail` (`user-settings.swift:192, 311, 341`) — note the *field* is named `packageDetail`, and `package` is a banned word
- `HoldingInfo.support.message` and the CLI's own stage `detail` (`wizard.swift:3332-3342`)
- `ConnectionsRender.unavailableDetail` → `report.detail` (`render-state.swift:405`)
- Every `AdminRunRow` failure `detail` (`admin-support.swift:1061-1062`)

**Consequence:** every banned term in this document is enforceable in Swift only for app-authored strings. For CLI-authored strings the ban must be enforced in the `cc` helper (the `claude-copilot` repo), because Control Tower is architecturally forbidden from rewriting them. The app *does* apply one important guard already — `HoldingInfo.isPresentable` (`wizard.swift:633`) gates whether a CLI detail is allowed to appear inline as a headline versus being demoted into the collapsed "Details for support" block — but presentability is not a vocabulary check.

This is a real, open gap and it belongs in the CLI contract, not in a lint on `native/*.swift`.

### The enforcement gap

There is **no automated check** that any of the above holds. The 40 `fitness_*.rs` tests that encode product rules — including `fitness_no_eta_in_wizard.rs`, which enforces the no-time-estimates rule that this document also states — all scan `src-tauri/src/**`, the retired Rust tree. They cannot see a single line of the shipping Swift, and the CI job that runs them is disabled behind `vars.RELEASE_CI_ENABLED`. Every voice rule in this document is currently upheld by review, not by a gate. That is the same honest gap recorded as **G-1** across this rebuild; leak #1 above is what an unenforced rule looks like after seven releases.

---

## Implementation Notes

- **Dynamic content.** `{Copilot}` is data, never a hardcoded enum — resolved through `displayName(forProduct:)` (`render-state.swift:47-55`) with a `\(product.capitalized) Copilot` fallback so a fifth component names itself correctly. `{Layer}` must always pass through `plainLayer()` (`render-state.swift:59-67`) or the `LayerDot.plainLabels` table (`tray.swift:1318-1323`) before reaching a sentence. Leak #8's hardcoded `four copilots` is the counter-example.
- **The two mapping tables are duplicated.** `plainLayer()` in `render-state.swift` and `LayerDot.plainLabels` in `control-tower-tray.swift` encode the same decision with different wording (`core setup` versus `Core setup`, `organization` versus `Your organization`) — one is for mid-sentence prose, the other for standalone labels. That split is defensible; the fact that a third code path (`layer.label`) bypasses both is not.
- **Fail-closed copy.** An unrecognized future value must never render as ready. `ConnectionsRender.noStoreRows` groups an unknown `secret_state` with the no-store rows precisely so it still gets an honest explanation instead of being silently dropped (`render-state.swift:386-388`). Any new enum with a copy mapping should follow that shape.
- **Never print a fabricated placeholder.** `HoldingSupportInfo` uses one optional Swift property per optional printed line so a value the app never had is **omitted** rather than printed as `unknown` (`wizard.swift:530-548`). A missing line is honest; a placeholder is not.
- **Character budget.** The popover is a fixed `360pt` wide (`tray.swift:1504`). The status sentence is the headline and wraps via `.fixedSize(horizontal: false, vertical: true)`, so long sentences grow the popover rather than truncate. Target one glanceable sentence.
- **VoiceOver.** Every status carries an accessibility label; the tray glyph and badge marks are `.accessibilityHidden(true)` so shape is never the only signal (`tray.swift:1302, 1345`). Leak #4 is the outstanding defect: two labels fall back to a raw enum `rawValue` instead of a phrase.
- **Localization.** English is the source. The load-bearing constraint for translators: **naming the specific copilot and the specific plain-language layer is semantic, not stylistic** — a translation that re-blends `Codex Copilot needs you to sign in. Everything else is fine.` into a single vague verdict has broken the product's core promise. Preserve `{Copilot}` and `{Layer}` as independent, ordered variables. <!-- TODO: confirm target locales; no localization infrastructure exists in native/ today. -->
- **Product name.** **Copilot Control Tower** (short: **Control Tower**). Shown to the user in the wizard chrome (`Set Up Copilot Control Tower`, `tray.swift:3510`), the wizard body, and Admin. It lives in the chrome, not in status sentences — status sentences stay about the reader's work.

---

## RECOMMENDATIONS — proposed copy, not shipped copy

Everything in this section is a **proposal**. None of it is in the v0.3.2 binary. Each entry pairs the shipped string with a replacement that keeps its meaning and drops the machinery. No code was changed to produce these.

| # | Leak | Shipped today | RECOMMENDED replacement |
|---|---|---|---|
| 1 | Tray component-tree detail line (`tray.swift:1375`) | `foundation: pass · organization: warn · department: pass · personal: pass` | Reuse the plain labels already in the same file, and name only what is not ready: `Your organization needs review. Everything else is ready.` When all four pass, render **nothing** — the row's `Ready` mark already carries it, and silence is the success state. |
| 2 | Wizard verify roster caption (`wizard.swift:5874`) | `Ready · foundation: pass · organization: pass · department: pass · personal: pass` | `Ready everywhere: core setup, your organization, your department, and this Mac.` |
| 3 | Verify progress line (`wizard.swift:5868`) | `Checking this Mac and its inherited layers…` | `Checking this Mac and everything your team shares with you…` |
| 4 | VoiceOver labels (`tray.swift:1387`, `1356`) | `Claude Copilot, warn` | `Claude Copilot, needs review` — reuse the same phrase the visible row already shows (`tray.swift:1373`), so sighted and screen-reader users hear the same words. |
| 5 | Settings loading line (`user-settings.swift:478`) | `Checking every Copilot repository and layer…` | `Checking every copilot, everywhere it lives…` |
| 6 | Repository-root cards (`user-settings.swift:533, 538, 550`; `wizard.swift:4086, 4095`) | `Copilot repository folder` · `New Copilot repositories are created or downloaded here…` · `…its repository is private, but its checkout stays visible…` | `Where your copilots live` · `New copilot spaces are created or downloaded here, beside the ones you already have.` · `Personal is yours. It's private on GitHub, and you can always see it in this folder.` Adopt Admin's **"spaces"** across the User face. |
| 7 | Settings layer explainer (`user-settings.swift:546`) | `Each Copilot shows Foundation, Organization, your joined Department, and Personal as separate evidence-backed layers.` | `For each copilot you can see four things, checked separately: the core setup, what your organization shares, what your department shares, and what's yours on this Mac.` |
| 8 | Detect summary (`wizard.swift:4082`) | `\(total) expected layers across four copilots. \(visible) are visible now; \(changes) need a setup action.` | `\(visible) of \(total) pieces are already here. \(changes) still need setting up.` Drops the banned noun and the hardcoded copilot count in one move. |
| 9 | Detect waiting state (`wizard.swift:4081`) | `Control Tower is waiting for a complete repository inventory.` | `Control Tower is still checking what's here.` |
| 10 | Detect Ready definition (`wizard.swift:4045`) | `Nothing is called Ready until every expected layer is visible, connected, synchronized, and verified.` | `Nothing is called Ready until every piece is here, connected, up to date, and checked.` Keep the sentence — it is one of the best statements of the product's standard. Only the nouns change. |
| 11 | History-state phrases (`wizard.swift:2344-2356`) | `\(name)'s history has diverged from the pinned version, and the content is different` | `\(name) has been changed here in a way I can't safely reconcile with your team's copy.` And for the unreadable case: `I couldn't read \(name), so I left it exactly as it is.` |
| 12 | The Git instruction (`wizard.swift:2254`) | `\(repositoryPhrase). Resolve it in Git, then run setup again.` | `\(repositoryPhrase). This one needs a person who works with code. Copy the details below and send them to whoever looks after your Mac, then run setup again.` — bring it into line with the §G handoff pattern, which always offers the delegation fork. |
| 13 | Guided-setup intro (`wizard.swift:4832`) | `Run the CLI-generated plan in a visible Terminal session…` | `Run the prepared plan in a visible Terminal window, then Control Tower will check the result on its own.` |
| 15 | Settings failure (`user-settings.swift:484, 486`) | `Control Tower couldn't check whether the ecosystem is complete.` | `Control Tower couldn't check whether everything is set up. Nothing was changed, and Control Tower won't call your setup ready without that check.` |
| 16 | Popover secondary line (`tray.swift:1533-1536`) | the raw machine hostname | `This Mac`, per copy deck §1.1. Keep the hostname for Admin and diagnostics only. |
| 17 | Ellipsis consistency (`tray.swift:1662, 2669, 2681`) | `Settings...` and `Settings…` both ship | Standardize on the single ellipsis character `…` across menu and popover. |

**Two open questions for the owner, carried forward from copy deck Appendix C:**

1. **The security-banner affordance.** The deck flags `Re-affirm your version` as engineer-speak and proposes `Confirm my setup`, while also noting the honest answer may be that this should not be the user's decision at all. No security-banner string ships in `native/` today, so the question is still open and unforced.
2. **"Department" as a universal word.** The whole department vocabulary assumes an org shape. Some organizations use teams, practices, or functions. `ADR-002` fixes the *slug* structure, not the *display* word. Worth confirming before the first outside organization adopts.

---

**Related:** [UX Design](50-ux-design.md) · [UI Design](60-ui-design.md) · [Copy Deck (ratified specification)](../../03-design/control-tower-copy-deck.md) · [Holding Copy Spec](../../40-initiatives/02-enac-self-onboarding/walkthroughs/holding-copy-spec.md) · [Org Question Copy Spec](../../40-initiatives/02-enac-self-onboarding/walkthroughs/org-question-copy-spec.md) · [Adopt & Honesty Copy Spec](../../40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-honesty-copy-spec.md) · [SOUL](../../../SOUL.md)
