# Copy spec: the `org-required` route (Copilot Control Tower, SURFACE 2)

> **Working design doc, carried forward from the session scratchpad so it isn't lost.** This is the spec behind commit `1aef610` (`fix(app): ask which organization, instead of failing at a question nobody asked`), the last of a five-commit sequence that starts with `holding-copy-spec.md` (this same directory). The ratified, current state of everything below lives in `docs/03-design/control-tower-copy-deck.md` §2.1.1/§2.1.2, §2.9's `Use a different organization` action and its H6/H7-self-serve rows, Appendix E, and in `docs/03-design/landing-site.md` §3.1/§6 — treat this file as the historical record of the reasoning that produced it, not as the live spec. See `docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-honest-setup-work-record.md` for the work-record account, including the case-sensitivity and offline-truthfulness bugs this spec's investigation surfaced in `claude-copilot`.

Final UX copy for one new wizard state. Extends `docs/03-design/control-tower-copy-deck.md`. Every string below is final and verbatim-ready; an implementer can follow this document literally without any other context.

**Ground truth this obeys:** the copy deck's voice paragraph and its eight hard rules, `SOUL.md` §7, repo-root `CLAUDE.md` invariants (especially #1 parse-never-compute, #4 security never weakened, #5 route by actor-competence), and the project's own standing rule that the non-technical user is the spec. No layer jargon reaches a user surface: no `rank`, `manifest`, `package`, `tier`, `alias`, `SSH`, `scope`, `token`, `OAuth`, `repo`, `repository`, `schema`, `parse`, `device`, `MDM`. `key` is permitted. First person, sentence case, warm, no exclamation marks, no em-dashes, no blame, no time estimates. Titles 50 characters or fewer. Buttons are verbs, never `OK`, `Dismiss`, `Close`, `Retry`, `Repair`, `Fix`, or `Force`.

---

## 1. The problem, and the recommendation that determines everything else

Sign-in needs the organization's GitHub App client id. That id now comes from a small public file the organization publishes, so a signed-out Mac can read it without authenticating first. But fetching it requires knowing *which* organization, and on a genuinely fresh Mac nothing does. So `cc auth login` returns a new error code, `org-required`, distinct from the existing `no-company-app`:

- `org-required` means nobody has told me which organization you're with.
- `no-company-app` means I know your organization, and its sign-in isn't set up yet. That is the existing H6 case and it stays exactly as it is.

Today the app never passes an organization and never sets one, so **every fresh Mac hits `org-required`** and falls through `holdingInfo(forExit2Code:)`'s `default:` branch to H2's `Something stopped me from reading your setup, so I won't guess.` That is the exact dead-end class this whole effort has been removing. The CLI cannot prompt, because it must stay non-interactive and machine-readable. Asking is the app's job.

### The recommendation

**We ask for the GitHub organization name, and we make sure almost nobody has to answer from memory. The primary path is not copy at all: the organization hands the name to the person. The typed field is the fallback.**

**Primary path (an artifact change, not a copy change).** The organization's own download page already exists as a per-org deployable artifact (`docs/03-design/landing-site.md` §3.1: org-branded, org-hosted, "Signed by `<Org>`"). It already knows the organization's name. It should print it, in a labeled block, copyable in one tap. The invitation email carries the same name in one plain line, for the person who never returns to the page. Strings in §7 below.

**Fallback path.** One field on an inline screen over Connect GitHub, shown only when nothing already knows the organization. Strings in §3.

**Resolution order the app exhausts before showing anything:**

1. An organization pointer already set on this Mac. Then `org-required` never fires at all, and no screen appears. This is the state the admin standup should leave its own Mac in (see §6.4).
2. The admin standup brief's `org` field, on a Mac where standup ran. Tried **silently**, with no screen. Reasoning in §5.
3. Ask. Render §2.1.1.

### Why not the alternatives

| Considered | Rejected because |
|---|---|
| Ask for the company's friendly name and resolve it to the GitHub name | There is no name-to-organization index to resolve against. We would be inventing a lookup service to save one paste. |
| Ask for the work email domain | Same problem, and it invites `acme.com` when the organization is `Acme-Co`. Nothing maps one to the other. |
| Bake the organization into a per-org build of the app | Two builds are already ratified (user, admin). A third axis means re-signing and re-notarizing per customer. Enormous cost, one saved paste. |
| A `copilotcontroltower://connect?organization=` deep link from the download page | **Deferred, not rejected.** See §8, Diff 2's own deferral paragraph, which records the reasoning in the deck. |
| Sign the person in with the publisher's own GitHub App first, then list their organizations and let them pick | Genuinely tempting: it needs no page and no memory. It fails on real organizations. Listing a person's memberships requires the publisher's App to be installed on that organization, and organizations that restrict third-party application access make their own membership invisible. It also puts the publisher in the identity path for every customer and costs an entire extra sign-in ceremony. |
| Read the organization from an existing local `gh` sign-in | Bob's fresh Mac has no `gh`. It would help only a developer's Mac, and the app cannot call GitHub itself (invariant #1), so it needs a new CLI verb. Deferred, not rejected: worth a `cc auth orgs --json` later. |
| Ask only for a pasted address, never a name | Anyone who has the address also has the name. Anyone who has neither is served by neither. The field should **accept** an address rather than **require** one. See §3's normalization rule. |

**One thing must be true for this copy to be honest.** The screen's intro tells the person the name is on the download page and in the email. If §7 does not ship, that sentence is a lie and this screen is a dead end with better manners. §7 is not optional decoration.

---

## 2. Where this lives, and why

**An inline screen over Connect GitHub, built from the same `StepShell` mechanism `§2.2.1 One question first` already uses over Detect.** No sidebar row, no step-number change, `accent` blue and never orange.

Justified against the deck's existing grammar:

- **Not a new wizard step.** It would renumber `Step N of 10` to eleven and add a permanent sidebar row for a screen most Macs must never see. The deck's posture, and SOUL §8's own success signal ("It only ever asks me about my own stuff"), is that a question you can answer for the person is a question you do not ask.
- **Not a Holding variant.** Holding's frame is "setup stopped." Setup has not stopped; it is missing one fact with an immediate, user-owned answer. §2.2.1 already settled this exact call for the adopt offer: an offer or a question is not a pause, so it takes `accent` blue and is structurally unreachable from Holding. `org-required` has the same shape.
- **Not an H7-style sheet.** Sheets in this deck are always behind a primary on a host screen (§2.9.2, §2.9.3). This screen is the host, and it has a sheet of its own (§4).
- **Inline over Connect GitHub is the only fit,** and the mechanism exists and is already built.

**Routing.** `org-required` is not a hold. `holdingInfo(for:origin:)` returns `nil` for it, exactly as it already does for `signed-out`, and `routeCliError` enters the organization question instead of Holding.

**Numbering.** The screen is **§2.1.1** and its sheet is **§2.1.2**, sitting between Welcome (§2.1, step 1) and Detect (§2.2, step 3) so the deck reads in built order. Connect GitHub's device-flow strings stay where they are, in §2.5.1.

---

## 3. §2.1.1 The organization question (the `org-required` route)

### Screen chrome

- **Eyebrow:** `BEFORE YOU SIGN IN`
- **Title:** `Which organization are you with?` (32 characters)
- **Tint:** `accent` blue, never orange. This is a question, not a pause.
- **Sidebar:** no row. **Step number:** unchanged.

### Intro, by how we got here

The first sentence is constant on purpose. Only the second changes.

- **Nothing known** (the ordinary fresh Mac, empty field): `Your organization sets up its own sign-in, so I need to know which one to ask. You'll find its name on the page you downloaded Control Tower from, and in the email that sent you there.`
- **This Mac's own standup name was tried and didn't work** (field prefilled with it): `Your organization sets up its own sign-in, so I need to know which one to ask. This Mac already set up Acme-Co, so I tried that first.`

There is no third variant. The second appears only when the app has already tried a name on the person's behalf and it did not resolve, so the screen never has to explain a value the person did not type.

### The field

- **Label:** `Your organization's name on GitHub`
- **Placeholder:** `Acme-Co`
- **Helper text, always present, under the field:** `The short name in your organization's GitHub address, like the Acme-Co in github.com/Acme-Co.`

**Paste normalization (behavior, no copy, and that is the point).** The field accepts a full address and keeps the name out of it, rewriting itself in place with no message: `https://github.com/Acme-Co`, `github.com/Acme-Co/copilot-bootstrap`, and `github.com/orgs/Acme-Co/repositories` all become `Acme-Co`. The visible rewrite is its own feedback. Text the field cannot reduce is left exactly as typed and answered by validation, never silently discarded: a swallowed paste is worse than a wrong one.

### Footer

- **Leading actions, in order:** `Help me find it` (opens §2.1.2), then `Continue in the menu bar` (the deck's existing string, unchanged, and it never marks setup complete)
- **Primary action:** `Continue to sign in`
- **Primary disabled hint, empty field:** `Add your organization's name, or select Help me find it.`

### What happens after each action

| Action | What happens |
|---|---|
| `Continue to sign in` | The app calls `cc auth login --org <name> --json`. On success the screen goes away and Connect GitHub renders §2.5.1's ordinary code card. No confirmation and no toast: silence is the success state. Only once the sign-in ceremony has actually started does the app persist the pointer with `cc config set github_app.org <name>`, so a name that never resolved is never written to this Mac. |
| `Help me find it` | Opens the §2.1.2 sheet. Returns to this screen with focus in the field. |
| `Continue in the menu bar` | Closes the wizard. The tray keeps rendering what the CLI reports, which by construction is `setup-needed`. Setup is never marked complete. |

### Validation

Shown only after the field has been left or the primary pressed, never while the first characters are being typed. This is the same `orgSlugTouched` discipline Admin's own organization field already uses.

| Condition | Message | Extra affordance |
|---|---|---|
| Contains spaces | `Your organization's name on GitHub is one word, with dashes instead of spaces. Acme Corporation is usually Acme-Corporation.` | Button `Use Acme-Corporation`, which fills the field and enables the primary |
| Contains `@` | `That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.` | none |
| Anything else GitHub would not accept | `Names on GitHub use letters, numbers, and single dashes, and nothing else.` | none |

**Dynamic pattern for the spaces case:** `Your organization's name on GitHub is one word, with dashes instead of spaces. <what they typed> is usually <the same with runs of spaces turned into single dashes>.` The button reads `Use <the same with runs of spaces turned into single dashes>`. Echo their own value back so they can see the transform on the thing they actually typed.

### What comes back from the CLI

| CLI result | What the person sees |
|---|---|
| Device code returned | Connect GitHub's ordinary code card (§2.5.1). No confirmation, no toast. |
| `org-not-found` (new code, §6.1) | Stays on this screen. Under the field: `I couldn't find Acme-Coo on GitHub. It may be spelled differently there, and whoever looks after your Mac will know.` The field keeps what was typed so the difference stays visible, and `Help me find it` is already in the footer. |
| `no-company-app` | H6, or H7 self-serve on an admin Mac, both unchanged, plus the new `Use a different organization` leading action (§5). The organization is real and has not published yet. That is never the person's mistake and must never read as one. |
| `network-unavailable` (new code, §6.3) | H5, offline, existing intro verbatim: `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` |
| The pointer could not be written to this Mac | H2 with the existing `environment-error` intro, verbatim: `Something on this Mac stopped the setup helper, so I've paused.` Nobody's fault, and nothing new to invent. |

---

## 4. §2.1.2 Finding your organization's name (the sheet behind `Help me find it`)

Follows §2.9.2's precedent exactly: one deliberate tap, and a block whose label says who the contents are for. The inversion is the interesting part. In §2.9.2 the block holds a command for a technical person to run. Here the person is not missing a command, they are missing a fact, and the fact belongs to their admin. So the copyable block is **the message that asks for it**, already written. That is invariant #5 applied to copy: when the fix is not theirs, hand them the shortest route to whoever owns it.

- **Title:** `Finding your organization's name` (32 characters)
- **Intro:** `It's on the page you downloaded Control Tower from, and in the email that sent you there. If you can't find either, send this to whoever looks after your Mac.`
- **Block label:** `The message`
- **Block contents, verbatim and copyable:** `Hi, I'm setting up Copilot Control Tower on my Mac. It's asking for our organization's name on GitHub, the short name in our GitHub address. Can you send it to me?`
- **Copy affordance:** `Copy this message` / confirmed `Copied`
- **Primary:** `Done` (closes the sheet, returns focus to the field)

The sheet offers no link to GitHub. Opening the organization's page on GitHub requires knowing the organization, which is the thing they do not have.

---

## 5. The admin case, and the escape from H6

### The admin standup brief: try it silently

**Prefill silently. No confirmation screen.**

The standup brief on this Mac already carries `org` at its top level (`~/Library/Application Support/CopilotControlTower/standup-brief.json`), beside the `github_app.client_id` that H7 self-serve already reads. `LocalAdminSignal` gains a `standupOrgName` that reads it the same way: trimmed, `nil` on any read failure or blank field, never a fabricated placeholder.

**The rule:** on `org-required`, if `standupOrgName` resolves and has not already been tried this session, the app retries `cc auth login --org <briefOrg> --json` immediately, rendering nothing. If that succeeds, the person never sees §2.1.1 at all. If it does not, they land on the screen or the hold the result actually calls for, and the second intro variant tells them where the name came from.

**Why silent and not confirm.** A confirmation screen here would consist entirely of "this Mac already set up Acme-Co, press Continue." Its whole content is *everything is fine*, and that is the one thing this product refuses to render anywhere else: silence is the success state, there is no green checkmark reward, and the app never celebrates being healthy. Invariant #5 points the same way: auto-act on reversible things, and ask only about non-deferrable decisions on the person's own data. Adopting an organization name that this Mac's own admin app wrote, minutes ago, from a value the admin typed with their own hands, is maximally reversible and is not a decision. H7 self-serve reads the same brief and still shows a screen, but for a different reason: there the fix is a Terminal command the app genuinely cannot run. This one the app can run.

**Three things make silence safe:**

1. **Nothing is persisted until it works.** The pointer is written only after the sign-in ceremony actually starts, so an unusable name from a stale brief leaves nothing behind on this Mac.
2. **Every failure is visible and explained.** `org-not-found` lands on §2.1.1 with the field prefilled and the second intro variant naming the source. `no-company-app` lands on H6 or H7 self-serve, both of which now carry a way back to the field. `network-unavailable` lands on H5.
3. **The value is local and self-authored.** It came from a file this Mac's own admin app wrote during a standup run at this Mac. Anything able to forge it already owns the account.

### The better fix, one layer up

The narrow case above exists because standup does not currently leave the pointer behind. **Admin standup should write `github_app.org` itself**, at the moment it writes the brief. Then resolution-order step 1 covers the admin's Mac, `org-required` never fires there, and the brief branch degrades to a recovery path for Macs whose standup predates that change. Recorded as an admin-flow ask in Appendix E.3.

### `Use a different organization`: the escape from H6

**H6 and H7 self-serve gain one leading action, `Use a different organization`, shown only when the hold was reached from §2.1.1.**

Without it, one real-but-wrong name is a permanent trap. `Acme` and `Acme-Co` may both be real organizations on GitHub. Type the first when you meant the second and today you are told your organization hasn't finished setting up sign-in, and you wait forever on an admin who has nothing to fix. The action returns to §2.1.1 with the field populated, so the correction costs one keystroke, and nothing was persisted, so it costs nothing else.

**Which intro variant on return:** variant 2 when the value came from the standup brief; variant 1 in every other case, because a person returning to a value they typed themselves does not need to be told where it came from, but does still benefit from being told where to find the right one.

---

## 6. What the CLI has to change first, and three bugs this uncovered

I traced `org-required` to its consumer rather than its producer. `core/ecosystem/bootstrap_config.py`'s `fetch_org_client_id()` fails open to `None` for every failure it meets, and `commands/auth.py`'s `_resolve_client_id()` turns every one of those into `no-company-app`. Its docstring says it "deliberately does not distinguish those cases from each other, since none of them are actionable by the person signing in." **That reasoning was correct before this screen existed and is wrong now.** The moment the app asks a human for the organization name, three of those collapsed cases become differently-owned, and one becomes the person's own text field.

### 6.1 Bug 1: the organization comparison is case-sensitive

`fetch_org_client_id` does `data.get("org") != org` on an exact string (`bootstrap_config.py:125`). A person told "Acme-Co" who types `acme-co`, or who pastes a lowercase address, gets a mismatch, a fail-open `None`, and H6 telling them their organization hasn't finished setting up sign-in. It has.

GitHub logins are case-insensitive and unique by fold, and commit `401b585` already established that real organization names are capitalized and must be used verbatim. **The comparison must fold case. The value must still be sent to GitHub exactly as published.** Without this fix, the single most likely input error in the entire flow lands on the variant reserved for "not your fault, wait for your admin." This is the one I would fix first.

### 6.2 Bug 2: a typo and a real-but-unpublished organization share one code

`org-not-found` must exist as a distinct code, produced by an unauthenticated check that the organization resolves on GitHub at all.

**Its fail direction is load-bearing.** An inconclusive probe, including a rate-limited one, must degrade to `no-company-app`, never to `org-not-found`. Telling someone their real organization does not exist is a worse failure than making them wait, and `api.github.com`'s 60-per-hour unauthenticated limit is shared by everyone behind a single corporate address, so inconclusive answers will be real and routine. Which probe to use is the CLI's call. The fail direction is not negotiable.

### 6.3 Bug 3: an offline Mac is told a falsehood

A network error inside `fetch_org_client_id` currently becomes `no-company-app`, so an offline person reads "Your organization hasn't finished setting up sign-in yet." That is a fabricated state, which the deck's hard rule 6 forbids, and H5 already exists for exactly it. `network-unavailable` must be its own code.

### 6.4 Summary of asks

| Where | Ask |
|---|---|
| `cc auth login --json` | Fold case when comparing the bootstrap file's `org`. Send the value to GitHub verbatim. |
| `cc auth login --json` | New error code `org-not-found`. Inconclusive probes degrade to `no-company-app`. |
| `cc auth login --json` | New error code `network-unavailable` for a transport failure fetching the bootstrap file. |
| Admin standup | Write `github_app.org` when the brief is written, so the question never arises on the admin's own Mac. |

None of these can be worked around in the app, because the app must parse and never compute (invariant #1). **They land before the screen ships, or the screen relocates the dead end instead of removing it.**

---

## 7. What the page and the email must carry

Additions to `docs/03-design/landing-site.md` §3.1, placed directly under the three install steps. Without these, §2.1.1's intro is untrue.

- **Block label:** `When Control Tower asks which organization you're with`
- **The name, rendered as copyable text:** `Acme-Co`
- **Copy affordance:** `Copy` / confirmed `Copied`
- **Quiet line under it:** `Copy this and paste it in when Control Tower asks. It's the only thing you'll need to type.`

Addition to the invitation email (walkthrough screen 1.1), one line near the download link:

- `When it asks which organization you're with, the answer is Acme-Co.`

The organization's name on GitHub is not a secret and is not org configuration in the sense the landing-site brief's admin bullet forbids: the page already prints "Signed by `<Org>`", and the file it names is public by construction. The page still carries no admin materials, no client secret, and no download of the admin build. (Owner confirmed.)

---

## 8. Deck diff, ready to apply to `docs/03-design/control-tower-copy-deck.md`

### Diff 1: amend the SURFACE 2 preamble

Replace the two paragraphs beginning "One guided window, **ten** steps":

> One guided window, **ten** steps in the built flow, plus **three** first-class inline screens that add no sidebar row and change no step number: the **holding** screen (§2.9), the **organization question** (§2.1.1), and the **one question first** screen (§2.2.1). No time estimates anywhere. Step position reads as `Step N of 10`, sentence case, never a clock.
>
> **Two steps have no section of their own below.** `Connect GitHub` (step 2) is the device-flow sign-in, whose strings live in §2.5.1 and whose one inline question lives in §2.1.1. `Your projects` (step 7) is specified in full in `docs/40-initiatives/02-enac-self-onboarding/walkthroughs/adopt-and-project-setup-spec.md`. The eyebrows in §2.2 through §2.8 below carry their correct built positions.

### Diff 2: insert §2.1.1 and §2.1.2 immediately after §2.1 Welcome

> ### 2.1.1 Which organization are you with? (inline over Connect GitHub)
>
> Rendered the way Holding and §2.2.1 are rendered: a `StepShell` over the Connect GitHub stage, no sidebar row, no step-number change, `accent` blue and never orange, because this is a question and not a pause. Entered when `cc auth login --json` returns `org-required`, which on a genuinely fresh Mac is every time. Sign-in needs the organization's GitHub App sign-in ID, that ID now comes from a small public file the organization publishes, and fetching it means knowing which organization. Nothing on a fresh Mac does. The CLI cannot ask, because it must stay non-interactive and machine-readable, so asking is the app's job.
>
> **Never a Holding variant.** `holdingInfo(for:origin:)` returns `nil` for `org-required`, exactly as it already does for `signed-out`, and `routeCliError` enters this screen. Before this section, `org-required` fell through to H2's `Something stopped me from reading your setup, so I won't guess.` on every fresh Mac, which is the failure class §2.10 exists to remove.
>
> **The app exhausts everything it can know before it asks.** First, an organization pointer already set on this Mac, in which case `org-required` never fires and no screen appears. Then the admin standup brief's `org` field, tried **silently** with nothing rendered (§2.1.1's own admin rule below). Only then does it ask.
>
> - Eyebrow: `BEFORE YOU SIGN IN`
> - Title: `Which organization are you with?`
> - Intro, by how we got here (the first sentence is constant; only the second changes):
>   - Nothing known, empty field: `Your organization sets up its own sign-in, so I need to know which one to ask. You'll find its name on the page you downloaded Control Tower from, and in the email that sent you there.`
>   - This Mac's own standup name was tried and didn't work, field prefilled with it: `Your organization sets up its own sign-in, so I need to know which one to ask. This Mac already set up Acme-Co, so I tried that first.`
> - Field label: `Your organization's name on GitHub`
> - Placeholder: `Acme-Co`
> - Helper text, always present: `The short name in your organization's GitHub address, like the Acme-Co in github.com/Acme-Co.`
> - Leading actions: `Help me find it`, then `Continue in the menu bar`
> - Primary action: `Continue to sign in`
> - Primary disabled hint, empty field: `Add your organization's name, or select Help me find it.`
>
> **The field takes an address as happily as a name.** `https://github.com/Acme-Co`, `github.com/Acme-Co/copilot-bootstrap`, and `github.com/orgs/Acme-Co/repositories` all rewrite in place to `Acme-Co`, with no message: the visible rewrite is the feedback. Text it cannot reduce is left exactly as typed and answered by validation, never silently discarded.
>
> **Validation**, shown only after the field is left or the primary is pressed, never while the first characters are typed (Admin's own `orgSlugTouched` discipline):
>
> | Condition | Message | Extra affordance |
> |---|---|---|
> | Contains spaces | `Your organization's name on GitHub is one word, with dashes instead of spaces. Acme Corporation is usually Acme-Corporation.` | Button `Use Acme-Corporation` |
> | Contains `@` | `That's an email address. I need your organization's name on GitHub, which is usually one word with dashes.` | none |
> | Anything else GitHub would not accept | `Names on GitHub use letters, numbers, and single dashes, and nothing else.` | none |
>
> The spaces message and its button both echo the person's own typed value back, with runs of spaces turned into single dashes, so the transform is shown on the thing they actually typed.
>
> **What comes back:**
>
> | CLI result | Where it goes |
> |---|---|
> | Device code returned | Connect GitHub's ordinary code card (§2.5.1). No confirmation and no toast: silence is the success state. |
> | `org-not-found` | Stays here. Under the field: `I couldn't find Acme-Coo on GitHub. It may be spelled differently there, and whoever looks after your Mac will know.` The field keeps what was typed, so the difference stays visible. |
> | `no-company-app` | H6, or H7 self-serve on an admin Mac, both unchanged, plus the `Use a different organization` action §2.9 now carries. The organization is real and has not published yet. That is never the person's mistake and must never read as one. |
> | `network-unavailable` | H5, offline, existing intro verbatim. |
> | The pointer could not be written to this Mac | H2 with `environment-error`'s existing intro, verbatim. |
>
> **The pointer is written only after the sign-in ceremony actually starts** (`cc config set github_app.org <name>`, machine config, once the device code comes back). A name that never resolved is never persisted, so a wrong answer costs one keystroke and leaves nothing behind.
>
> **The admin's own Mac: try the standup name silently.** The standup brief already carries `org` beside the `github_app.client_id` H7 self-serve reads. On `org-required`, if that name resolves and hasn't already been tried this session, the app retries with it and renders nothing; a success means the person never sees this screen. A confirmation screen here would consist entirely of "this Mac already set up Acme-Co, press Continue," and a screen whose whole content is *everything is fine* is the one thing this deck refuses to render anywhere else. Three things make silence safe: nothing is persisted until sign-in actually starts, so a stale name leaves nothing behind; every failure is visible and explained, landing on this screen's second intro variant or on a hold that carries a way back; and the value came from a file this Mac's own admin app wrote from something the admin typed by hand. H7 self-serve reads the same brief and still shows a screen, but for a reason that doesn't apply here: there the fix is a command the app genuinely cannot run. The standup should also write the pointer itself (Appendix E.3), after which this branch is only a recovery path for Macs set up before that change.
>
> **Handing the name over instead of asking for it: what was deferred.** A `copilotcontroltower://connect?organization=` link from the org's download page would remove the paste entirely, and it was designed and then deferred rather than rejected. It registers a URL handler in both builds that anything on the machine can invoke, on the one code path that runs before any credential exists, and to stay safe it would have to render a confirmation screen anyway, so it buys a saved paste at the cost of new externally-triggerable surface. The copyable name on the page (Appendix E.2) carries nearly all of the benefit with none of that. Revisit once the flow has real usage.
>
> ### 2.1.2 Finding your organization's name (the sheet behind `Help me find it`)
>
> §2.9.2's pattern, inverted. There, the block holds a command for a technical person to run. Here the person is not missing a command, they are missing a fact, and the fact belongs to their admin. So the copyable block is the message that asks for it, already written. Actor-competence (invariant #5): when the fix is not theirs, hand them the shortest route to whoever owns it.
>
> - Title: `Finding your organization's name`
> - Intro: `It's on the page you downloaded Control Tower from, and in the email that sent you there. If you can't find either, send this to whoever looks after your Mac.`
> - Block label: `The message`
> - Block contents, verbatim: `Hi, I'm setting up Copilot Control Tower on my Mac. It's asking for our organization's name on GitHub, the short name in our GitHub address. Can you send it to me?`
> - Copy affordance: `Copy this message` / confirmed `Copied`
> - Primary: `Done` (closes the sheet, returns focus to the field)
> - The sheet never links to GitHub: opening the organization's page requires the very thing they don't have.

### Diff 3: amend §2.9's Actions paragraph, and add one paragraph after it

Append to the closed action set, after `Show me the command`:

> · `Use a different organization` (H6 and H7 self-serve, **only** when the hold was reached from §2.1.1; returns there with the field populated)

New paragraph immediately after the Actions paragraph:

> **Why H6 needs a way back.** `Acme` and `Acme-Co` can both be real organizations on GitHub. Type the first when you meant the second and H6 is truthful about what it found and useless about what to do: you are told your organization hasn't finished setting up sign-in, and you wait on an admin with nothing to fix. `Use a different organization` exists for that one case and appears nowhere else. It is not a retry, because nothing failed. It is the correction of an answer given two screens earlier, and it costs one keystroke because nothing was persisted. Returning shows §2.1.1's second intro variant when the name came from this Mac's standup brief, and its first in every other case.

### Diff 4: one row in Appendix A

> | `Which organization are you with?` | `Set github_app.org to your organization slug.` |

### Diff 5: new Appendix E, after Appendix D and before the closing note

> # Appendix E: The organization question, contract additions and carriers
>
> §2.1.1 asks a person for a value. That single fact changes who owns three failures the CLI currently collapses into one code, and it puts a fourth on the person's own field. `core/ecosystem/bootstrap_config.py`'s `fetch_org_client_id()` fails open to `None` on every network, format, and mismatch problem alike, and `commands/auth.py`'s `_resolve_client_id()` renders all of them as `no-company-app`. Its docstring's reasoning, that none of these are actionable by the person signing in, was true before this screen existed and is false now.
>
> ## E.1 Contract additions
>
> | Verb | Addition | Why the app needs it |
> |---|---|---|
> | `auth login --json` | The bootstrap file's `org` comparison folds case. The value is still sent to GitHub exactly as published. | A person told `Acme-Co` types `acme-co`. Today `data.get("org") != org` is an exact match, so that fails open and renders H6, telling them their organization hasn't finished setting up sign-in when it has. This is the most likely single input error in the flow, and it currently lands on the variant reserved for "not your fault, wait." GitHub logins are case-insensitive and unique by fold, and commit `401b585` already settled that the name is used verbatim and never lowercased. |
> | `auth login --json` | New error code `org-not-found`, from an unauthenticated check that the organization resolves on GitHub at all. **An inconclusive or rate-limited probe degrades to `no-company-app`, never to `org-not-found`.** | Separates "the name I was given isn't an organization on GitHub" (§2.1.1's own field, one keystroke) from "your organization hasn't published its sign-in yet" (H6, their admin's). Without it every typo becomes an indefinite wait on someone with nothing to fix. The fail direction is load-bearing: telling someone their real organization doesn't exist is worse than making them wait, and the unauthenticated GitHub rate limit is shared by everyone behind one corporate address. |
> | `auth login --json` | New error code `network-unavailable` for a transport failure fetching the bootstrap file. | Today an offline Mac is told its organization hasn't finished setting up sign-in. That is a fabricated state, which hard rule 6 forbids, and H5 already exists for it. |
>
> ## E.2 The carriers, so §2.1.1's intro is true
>
> §2.1.1 tells the person the name is on the download page and in the email. Both must carry it, or the sentence is a lie and the screen is a dead end with better manners.
>
> **`landing-site.md` §3.1, directly under the three install steps:**
>
> - Block label: `When Control Tower asks which organization you're with`
> - The name, copyable: `Acme-Co`
> - Copy affordance: `Copy` / confirmed `Copied`
> - Quiet line: `Copy this and paste it in when Control Tower asks. It's the only thing you'll need to type.`
>
> **The invitation email (walkthrough screen 1.1), one line near the download link:** `When it asks which organization you're with, the answer is Acme-Co.`
>
> The organization's name on GitHub is not a secret and is not org configuration in the sense §1's admin bullet forbids: the page already prints "Signed by `<Org>`", and the file it names is public by construction. The page still carries no admin materials, no client secret, and no download of the admin build. (Owner confirmed.)
>
> ## E.3 App-side and admin-side plumbing this copy depends on
>
> - `holdingInfo(forExit2Code:)` gains `case "org-required": return nil`, beside the existing `signed-out` case, and `routeCliError` enters the organization question rather than Holding when `nil` comes back from that code.
> - `CliClient.authLoginInitiate()` and `authLoginPoll(deviceCode:)` both take an optional organization and pass `--org`. The poll needs it too: `build_auth_poll_report` re-resolves the client id on every call.
> - `LocalAdminSignal` gains `standupOrgName`, reading `org` from `standup-brief.json` exactly as `standupGitHubAppClientID` reads `github_app.client_id`: trimmed, `nil` on any read failure or blank field, never a fabricated placeholder.
> - **Admin standup writes `github_app.org` when it writes the brief.** Then the admin's own Mac never reaches `org-required` at all, and §2.1.1's silent brief branch is only a recovery path for Macs whose standup predates that change.
> - The user wizard has no text field today. This is its first. Admin's organization field (§3.7) is the visual reference, and its `orgSlugTouched` gating is the validation-timing reference.
>
> ## E.4 Open contract question
>
> This section assumes the app persists the pointer with `cc config set github_app.org <name>`, which is what `commands/auth.py`'s own docstring names as the app's job ("the app sets this once via `cc config set github_app.org <org>` after collecting it during onboarding"), so the CLI already anticipated this screen. But `cc config set` prints human text and has no `--json` output, so the app can read only its exit code. Whether that is acceptable under the versioned contract, or whether persistence needs a machine-readable verb of its own, is unresolved and owner-owned. The copy above does not depend on the answer: no string claims the value was saved, and the only failure path ("the pointer could not be written to this Mac") routes to an existing H2 intro.

---

## 9. Implementation notes

- **Character limits.** Titles 50. Inline validation lines wrap to two lines at 160. The intro's second sentence carries a name of up to 39 characters (GitHub's own limit), so lay it out for the long case.
- **Dynamic content.** `Acme-Co`, `Acme-Coo`, and `Acme Corporation` in the strings above are placeholders for the person's own value, echoed back exactly as typed or as published. Never case-folded for display, never truncated, never localized.
- **Localization.** `github.com/Acme-Co` in the helper text is a literal address and does not translate. The copyable message in §2.1.2 does translate; it is prose a human reads.
- **Accessibility.** The validation line and the `Use Acme-Corporation` button are announced as one message, so a screen-reader user is never offered a fix without the reason for it.
- **No new vocabulary.** Every string above uses words already in the deck: `organization`, `GitHub`, `name`, `address`, `sign in`, `this Mac`, `whoever looks after your Mac`. Nothing from Appendix B appears.

---

## 10. Flags

1. **Deferred, per owner decision:** the `copilotcontroltower://connect` deep link. Recorded in the deck (Diff 2) with the reasoning, revisitable once the flow has real usage.
2. **I did not verify which unauthenticated probe the CLI should use** for `org-not-found`. That is the CLI's call. The only thing this spec is firm about is the fail direction: inconclusive degrades to `no-company-app`.
3. **`cc config set` is exit-code-only.** Recorded as an open contract question in Appendix E.4 rather than resolved here. No copy depends on the answer.
4. **Landing-site "no org configuration" constraint:** resolved. Owner confirmed the organization's public name on the page is fine.
