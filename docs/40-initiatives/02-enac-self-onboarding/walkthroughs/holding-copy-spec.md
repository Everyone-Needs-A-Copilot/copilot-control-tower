# Copy spec: the wizard Holding screen (`.holding`)

> **Working design doc, carried forward from the session scratchpad so it isn't lost.** This is the spec behind commit `dca7e58` (`fix(app): say why setup is holding, and never call your own work a failure`), the first of a five-commit sequence. It documents Holding as **six** variants (H1–H6); two later commits in the same sequence (`9d4730f`, `a3884b0`) added a **seventh**, H7 ("something only you can do"), and a companion completion-rule pattern (§2.10). The ratified, current state of all of this lives in `docs/03-design/control-tower-copy-deck.md` §2.9–§2.10 — treat this file as the historical record of the reasoning that produced it, not as the live spec. See `docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-honest-setup-work-record.md` for the work-record account and `adopt-and-honesty-copy-spec.md` (this same directory) for H7 and the completion rule.

**Scope:** user-facing strings, variant taxonomy, and action wiring for `native/wizard.swift`'s `.holding` phase (`holdingView`, `genericHoldingReason`, `holdingReason(forNonHealthy:)`, `enterHolding`, `tryAgainAfterHolding`). No Swift here. Every string below is final; ship it verbatim.

**Governing voice:** `docs/03-design/control-tower-copy-deck.md` (§1.2 reason vocabulary, §2.9 Holding). No em-dashes, sentence case, first person, no exclamation marks, no time estimates, no blame, no jargon in headline copy. Precise technical terms are correct *only* inside the collapsed support block.

**The strategy, stated once (invariant #5):** every variant below is addressed to exactly one actor. H1 is addressed to whoever installs software on this Mac. H2/H3 are addressed to nobody (the app retries; the user just needs to not be lied to). H4 is addressed to the user, because it is a non-deferrable decision about the user's own data. H5 is addressed to nobody (wait). H6 is addressed to IT, via the user as courier. The variant is chosen by *who owns the fix*, never by *what went wrong*.

---

## 1. State taxonomy

Six variants replace the single screen. All six reuse the existing `StepShell` (eyebrow, title, intro, content, leading actions, primary action) and existing tokens from `control-tower-visual-system.md` §2.2. No new visual system.

| # | Variant | When | Header tint (existing token) | Mark |
|---|---|---|---|---|
| H1 | **Not installed** | `CliError.notFound` | `setup-needed` `.secondaryLabelColor` | hollow ring |
| H2 | **Can't read your setup** | `CliError.launchFailed` / `.parse` / `.schemaOutOfRange` / `.missingSecurityField`, and unmapped `.exit2` | `cli-unreadable` `.systemRed` | filled circle + `!` |
| H3 | **Couldn't finish a part of setup** | a CLI stage returned `blocked` and the CLI did not classify it as held-for-you | `needs-attention` `.systemOrange` | filled triangle |
| H4 | **Something here is already yours** | a CLI stage returned `blocked` *and* the CLI classified it as held (invariant #3 working) | `accent` (default blue, no ramp color) | none |
| H5 | **Waiting** | `doctor.offline == true`, or exit-2 code `lock-contention` | `waiting-for-network` `.secondaryLabelColor` | clock |
| H6 | **Waiting on your organization** | exit-2 codes `onboard-unavailable` / `no-company-app`, or a blocked `secret-store` stage | `it-config-incomplete` `.secondaryLabelColor` | wrench |

**H1 is deliberately not red.** Nothing is broken when the CLI was never installed. It is `setup-needed`, the same neutral token the tray already uses for "let's finish setting you up." (Side note for the implementer, not copy: `native/render-state.swift:116` currently folds `.notFound` into `.ioError` for the tray. That mapping is now wrong in the same way this screen was. Flag it; do not fix it inside this change.)

**H4 must never be orange and must never use the word "paused", "stopped", "couldn't", "problem", or "error".** It is a success with a question attached.

### H1. Not installed

- Eyebrow: `ONE MORE PIECE TO INSTALL`
- Title: `The setup helper isn't installed yet`
- Intro: `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.`
- Content: none (no review card).
- Leading: `Continue in the menu bar`
- Leading: `Check again`
- Primary: `Show me how to install it`

### H2. Can't read your setup

- Eyebrow: `SETUP PAUSED`
- Title: `I can't read your setup, so I've paused`
- Intro: the per-reason line from §2 below, verbatim. One sentence, no stacking.
- Content: the support disclosure (§5). Nothing else.
- Leading: `Continue in the menu bar`
- Primary: `Try again`

### H3. Couldn't finish a part of setup

- Eyebrow: `SETUP PAUSED`
- Title: `I couldn't finish one part of setup`
- Intro: the per-gate sentence from §3 below, verbatim.
- Content: the framed CLI line where §3 says "frame" (§3.1), then the support disclosure.
- Leading: `Continue in the menu bar`
- Primary: `Try again`

### H4. Something here is already yours

- Eyebrow: `ONE THING TO DECIDE`
- Title: `Something here is already yours`
- Intro: the per-gate sentence from §3 below, verbatim.
- Content, in order: the framed CLI line (§3.1), then the card `What I left alone` (existing `ecosystemInventory` rows where `action == "review"`, title plus CLI `detail` verbatim, unchanged rendering), then the reassurance line `Nothing was changed, moved, or removed.` in caption gray, then the support disclosure.
- Leading: `Include what I already have` (existing behavior: only when `onboardQuestionItems` is non-empty)
- Leading: `Continue in the menu bar`
- Secondary (see §4 for availability): `Let setup manage it`, otherwise `Check again`
- Primary: `Keep what I have`

**H4 confirmation state** (after `Keep what I have`, same screen, body replaced, no new window):

- Eyebrow: `ONE THING TO DECIDE`
- Title: `Kept as it is`
- Intro: `I left it exactly as it was. Control Tower keeps watch from the menu bar and picks this up if it ever changes.`
- Leading: `Check again`
- Primary: `Continue in the menu bar`

### H5. Waiting

Two bodies, one shell. Title varies with cause.

| Cause | Title | Intro |
|---|---|---|
| `doctor.offline == true` | `I'll pick this up when you're back online` | `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` |
| exit-2 `lock-contention` | `Something else is updating right now` | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` |

- Content: none. No support disclosure (there is nothing for IT to act on).
- Leading: `Continue in the menu bar`
- Primary: `Try again`

### H6. Waiting on your organization

- Eyebrow: `WAITING ON YOUR ORGANIZATION`
- Title: `Your organization has a bit left to set up`
- Intro: the per-cause line from §2/§3 below, verbatim. Always ends with `There's nothing for you to do.`
- Content: the support disclosure, expanded label caption reads `Send this to whoever looks after your Mac.`
- Leading: `Check again`
- Primary: `Continue in the menu bar`

H6 is the one variant whose primary is not a retry, because retrying cannot change the outcome. The forward action is to leave, and the app says so plainly.

---

## 2. Reason table for genuine faults (replaces `genericHoldingReason`)

One row per `CliError` case. The intro line is used verbatim as the variant's `intro`. Reason tokens are never shown, per §1.2's existing rule.

| `CliError` | Variant | Intro line (verbatim) | Primary |
|---|---|---|---|
| `.notFound` | **H1** | `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.` | `Show me how to install it` |
| `.launchFailed` | H2 | `The setup helper is on this Mac, but it wouldn't start just now, so I won't guess.` | `Try again` |
| `.parse` | H2 | `I can't read what's already on this Mac right now, so I won't guess.` (reuses §1.2 `parse_error`) | `Try again` |
| `.schemaOutOfRange` | H2 | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` (reuses §1.2 `schema_out_of_range`) | `Try again` |
| `.missingSecurityField` | H2 | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` (reuses §1.2 `missing_security_field`) | `Try again` |
| `.exit2(code:message:)` | by code, below | by code, below | by code, below |

`.notFound` no longer says "I can't read what's already on this Mac." Nothing exists to read. That old line is the misleading one and it is deleted from this path.

`.missingSecurityField` never offers a way past itself. No "continue anyway", no "skip this check". Invariant #4.

### 2.1 `.exit2` routing by code

The CLI's error code selects the variant. The CLI's message is presented per §2.2, never as the title.

| Code | Variant | Intro line (verbatim) |
|---|---|---|
| `signed-out` | **not a hold** | Do not enter Holding. Return to the Connect GitHub step and show its existing signed-out copy. |
| `lock-contention` | H5 (busy) | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` |
| `onboard-unavailable` | H6 | `I couldn't read your organization's setup from GitHub, so I've paused. There's nothing for you to do.` |
| `no-company-app` | H6 | `Your organization hasn't finished setting up sign-in yet. There's nothing for you to do.` |
| `invalid-manifest` | H2 | `The list of what you get can't be read right now, so I won't guess.` |
| `environment-error` | H2 | `Something on this Mac stopped the setup helper, so I've paused.` |
| `not-implemented`, `unsupported-scope`, `invalid-argument` | H2 | `Control Tower asked your setup for something it doesn't offer. An update should line them back up.` |
| any other code | H2 | `Something stopped me from reading your setup, so I won't guess.` (reuses §1.2 `exit_2`) |

The code string itself (`E_SCHEMA_RANGE`, `onboard-unavailable`, anything) never appears outside the support block. Not in the title, not in the body, not in a caption.

### 2.2 How a CLI-authored message is presented

Rules, in order:

1. **Never the headline.** The title and intro are always app-authored, from the tables above.
2. **Inline, framed, only if it is presentable.** Render it under the intro in a quiet card, label `What your setup reported:` in caption gray, message below it in body text, verbatim, `.textSelection(.enabled)`, capped at three lines with a `Show more` toggle.
3. **Presentable means all of:** 200 characters or fewer, no newlines, no `{`, `}`, `<`, `>`, and it does not contain `Traceback`, `Error:`, `Exception`, or a file path segment (`/Users/`, `.py:`). Fail any test and the message is not shown inline at all. It goes only into the support block, and the intro stands alone.
4. **Never interpolated.** It is never concatenated into an app sentence, never prefixed with "because", never wrapped in quotes inside a sentence. It gets its own labelled block or nothing.
5. **Always in the support block**, verbatim and uncapped, regardless of whether it was shown inline.

The existing `"\(detail) Nothing existing was changed."` concatenation at `wizard.swift:613` violates rule 4 and is removed. The reassurance line becomes its own caption row, as specified in H4.

---

## 3. The six blocked gates

Discriminator per gate is listed. All discriminators read a CLI-emitted enum token. None reads prose, none infers.

| Gate | Type | Discriminator | Variant | Intro line (verbatim) | CLI `detail` |
|---|---|---|---|---|---|
| `personal-packages` | **B** | any `inventory[]` item with `scope == "personal"` and `action == "review"` | H4 | `One of your own spaces on GitHub is set up in a way I don't recognize, so I left it exactly as it is.` | **frame** |
| `personal-packages` | A | blocked with no `review` inventory item | H3 | `GitHub didn't confirm one of your own spaces, so I stopped before changing anything.` | **frame** |
| `device-ssh` | **B** | `stage.config == "held"` or `stage.key == "incomplete"` | H4 | `This Mac already has a GitHub connection I didn't set up, so I left it exactly as it is.` | **replace** |
| `device-ssh` | A | any other blocked device-ssh stage | H3 | `I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed.` | **replace** |
| `layer-manifest` / `review` | **B** | `stage.action == "review"` | H4 | `I found settings on this Mac that I didn't set up, so I left them alone.` | **frame** |
| `secret-store` | A, IT-owned | blocked | **H6** | `Your organization's shared store isn't ready for this Mac yet. There's nothing for you to do.` | **replace** |
| `codex-plugin` | A | blocked | H3 | `I couldn't finish adding Codex Copilot on this Mac.` plus, only when the `materialize` stage's result is not `blocked`, ` Everything else finished.` | **replace** |
| `materialize` | **B** | `stage.held > 0` | H4 | `Some of your own unsaved work is in the way of an update, so I left it alone.` | **replace** |
| `materialize` | A | `stage.held == 0` | H3 | `Setting things up on this Mac didn't finish. Nothing that was already here was changed.` | **replace** |
| `doctor` | A | `status != healthy` at Verify | H3, title `I couldn't confirm everything's current` | the tray's existing per-status sentence from `RenderState.from(doctor:).header.sentence`, verbatim (unchanged behavior) | n/a |

`organization-handoff` is the seventh stage and never emits `blocked`; a handoff failure arrives as exit-2 `onboard-unavailable` and is handled in §2.1 as H6. Do not write copy for a blocked `organization-handoff`.

### 3.1 Frame vs replace

**Frame** means the CLI's `detail` is rendered verbatim beneath the app's intro, under the caption `What setup found:`, in body text. Use frame where the CLI's own string was already written for a non-technical reader. Verified examples that must survive untouched: `I don't recognize how this space is set up, so I'll leave it exactly as it is.` / `Something of yours is already using this name publicly, so I stopped. Nothing existing was changed.` / `This is set up through a link I don't manage, so I'll leave it untouched until it's looked at.` / `Your existing Claude or Codex setup isn't one I recognize, so I won't replace any of it.`

**Replace** means the CLI's `detail` never reaches the screen body. It goes into the support block only. Use replace where the string names machinery. Verified examples that must never be shown to the user: `An existing GitHub SSH alias is user-managed; setup did not replace it.` / `The Admin handoff is missing workspace_id, environment, or secret_path.` / `Codex could not register the verified local marketplace.` / `The verified Codex Copilot plugin was not materialized.`

The live-verified defect case (`device-ssh`, `An existing GitHub SSH alias is user-managed; setup did not replace it.`) therefore renders as: **H4, blue, `ONE THING TO DECIDE` / `Something here is already yours` / `This Mac already has a GitHub connection I didn't set up, so I left it exactly as it is.` / `Nothing was changed, moved, or removed.`** with `Keep what I have` as the primary. The raw sentence appears only under `Details for support`.

### 3.2 Pluralization for `materialize` with `held > 0`

Append one sentence to the H4 intro, chosen by count:

- `held == 1`: `I left one thing of yours untouched.`
- `held > 1`: `I left \(held) things of yours untouched.`

No other variant interpolates a number.

---

## 4. Actions, and what happens after each

Exact labels. Verbs only. `OK`, `Dismiss`, `Close`, `Retry`, `Repair`, `Fix`, and `Force` are all forbidden.

| Label | Emphasis | Appears in | What the wizard does next |
|---|---|---|---|
| `Try again` | primary | H2, H3, H5 | Existing `tryAgainAfterHolding()`: returns to the originating step's loading state. If it holds again with the same variant and the same reason, re-render the same screen and add one caption line under the intro: `Still the same. Nothing changed.` Show that line only from the second consecutive identical hold onward. |
| `Check again` | secondary | H1, H4, H4-confirmation, H6 | Identical behavior to `Try again`. Different word because nothing failed in these states, so "try again" would imply a failure that did not happen. |
| `Continue in the menu bar` | secondary (primary in H6) | all six | Closes the wizard window via `onClose()`. **Does not set `ct.hasCompletedFirstRun`.** The tray carries the state. This is the existing behavior and must not be "tidied up" into `finish(onClose:)`. |
| `Show me how to install it` | primary | H1 | Opens the install sheet (§4.1). |
| `Keep what I have` | primary | H4 | Records the decision for this session only. No CLI call, no write, nothing on disk. Replaces the screen body with the H4 confirmation state. The same question is not asked again this session. |
| `Let setup manage it` | secondary | H4, only when available (below) | Re-runs the originating stage passing the CLI's own consent token. On success the wizard continues normally. On a repeat block, H4 again with `Still the same. Nothing changed.` |
| `Include what I already have` | leading, quiet | H4, only when `onboardQuestionItems` is non-empty | Existing `returnToOnboardQuestion()`. Unchanged. |
| `Copy details` | inside the disclosure | H2, H3, H4, H6 | Copies the block from §5. Label swaps to `Copied` for two seconds, then back. No toast. |

**Availability of `Let setup manage it`:** render it only when the CLI declares that the gate accepts consent. Today exactly one consent path exists (`cc onboard --adopt-existing <components>`, personal packages) and it is consumed before the block, by the existing "One question first" screen. So today this button renders nowhere, and H4's secondary slot shows `Check again` instead. Do not wire it to anything speculative. Offering a user permission the CLI will not honor is the same lie this whole change exists to remove.

**Contract dependency (route to WS-A, `onboard.schema.json`).** Two additions make the taxonomy above fully CLI-driven instead of partly discriminator-derived:

1. `hold` on any stage with `result: "blocked"`, enum `"yours" | "fault"`. Direct H4-vs-H3 selection, computed where it belongs.
2. `consent` on a stage with `hold: "yours"`, the flag the app should pass back to let setup manage the thing. Its presence, and only its presence, renders `Let setup manage it`.

Until those land, use the discriminators in §3, decode the three `device-ssh` fields the CLI already emits (`key`, `registration`, `config`) onto `EcosystemOnboardStage`, and default to the fault variant whenever nothing proves otherwise. Claiming "this is yours" without proof is the one failure mode worse than the current screen.

**No dead ends.** Every variant has at least two exits, one of which always works offline and always works with a broken CLI: `Continue in the menu bar`. H6 additionally names the human who can act, and gives the user the artifact to hand them.

### 4.1 The install sheet (H1's forward step)

A sheet over the wizard, not a new window. This is how the install steps reach a non-technical user without dumping a shell command into the body copy.

- Title: `Installing the setup helper`
- Intro: `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.`
- Block label: `The steps`
- Block: the four lines from `docs/06-deployment/ground-up-claude-codex-installation.md:48-53`, in an existing `CopyableCodeBlock`, monospaced, selectable, never wrapped into prose.
- Copy button: `Copy these steps` / confirmed `Copied`
- Secondary link: `Open the install guide ›` opens `https://github.com/Everyone-Needs-A-Copilot/claude-copilot`
- Optional row, only if a file picker is actually implemented: `Already installed it somewhere else? ` + link `Choose it myself…`
- Primary: `Done`

`Done` closes the sheet and fires `Check again` once, automatically. The user should not have to find the button that proves the thing they just did.

The body of H1 never contains a command, a path, or the word `cc`. The command lives behind one deliberate tap, in a block whose label says who it is for.

---

## 5. Details for support (the collapsed diagnostic)

One component, one label, four surfaces (H2, H3, H4, H6). Collapsed by default, always. It is never open on first render and never expands itself.

- Disclosure label: `Details for support`
- Caption, visible only while expanded: `Send this to whoever looks after your Mac. It has nothing private in it.`
- Copy button: `Copy details` / confirmed `Copied` for two seconds
- Block style: existing mono block treatment (visual-system §2.1 code/handoff blocks), selectable

**Block contents, exactly this shape, one label per line, in this order:**

```
Copilot Control Tower <app version> (<build>)
Setup helper: <absolute path the app resolved>
Report format: <schema_version from the response>
Step: <raw stage id, e.g. device-ssh>
Result: <raw result, e.g. blocked>
Code: <error code, e.g. onboard-unavailable>
Message: <CLI message, verbatim, uncapped>
Recorded: <yyyy-MM-dd HH:mm>
```

Rules:

- Raw technical vocabulary is correct here. `device-ssh`, `schema_version`, and `E_SCHEMA_RANGE` belong in this block and nowhere else in the product.
- **Omit any line the app cannot fill.** Never print `unknown`, `nil`, `n/a`, or an empty value. A missing line is honest; a fabricated one is not. The CLI's own version is not currently captured by the app, so there is no `Setup helper version` line until something captures it. If a `cc --version` capture is added later, insert it as `Setup helper version: <value>` directly under `Setup helper:`.
- `Recorded:` is the single sanctioned timestamp in the product. The deck's "no time, ever" rule governs promises made to the user about the future. This is a fact about the past, in a block addressed to IT.
- The block is assembled from values already in hand. No new CLI call is made to populate it.
- VoiceOver: the disclosure is a real `DisclosureGroup` labelled `Details for support`; the copy button announces `Copy details`, then `Copied`.

---

## 6. Diff against `docs/03-design/control-tower-copy-deck.md`

Apply directly. §2.9 is replaced wholesale; two subsections are added after it; §1.2 gets one added row.

### 6.1 Replace lines 349 to 362 (all of §2.9) with:

```markdown
## 2.9 Holding (the honest terminal, never a dead end)

Holding is six variants, not one screen. The variant is chosen by **who owns the fix**, never by what went wrong. Two of the six are not failures at all: H4 is invariant #3 working correctly (setup found something the person already owns and refused to overwrite it), and H5/H6 are patience. Only H2 and H3 are faults.

| # | Variant | Eyebrow | Title | Tint (visual-system §2.2) |
|---|---|---|---|---|
| H1 | Not installed | `ONE MORE PIECE TO INSTALL` | `The setup helper isn't installed yet` | `setup-needed` neutral |
| H2 | Can't read your setup | `SETUP PAUSED` | `I can't read your setup, so I've paused` | `cli-unreadable` red |
| H3 | Couldn't finish a part | `SETUP PAUSED` | `I couldn't finish one part of setup` | `needs-attention` orange |
| H4 | Something is already yours | `ONE THING TO DECIDE` | `Something here is already yours` | `accent` blue, never orange |
| H5 | Waiting | `WAITING FOR THE NETWORK` | `I'll pick this up when you're back online` / busy: `Something else is updating right now` | `waiting-for-network` neutral |
| H6 | Waiting on your organization | `WAITING ON YOUR ORGANIZATION` | `Your organization has a bit left to set up` | `it-config-incomplete` neutral |

**Intro lines, by cause** (the reason is never a token, never raw CLI text as a headline):

| Cause | Variant | Intro |
|---|---|---|
| CLI not found on this Mac | H1 | `Control Tower works by reading a small helper on this Mac, and it isn't here yet. Installing it takes one step, and then I can pick up where I left off.` |
| CLI wouldn't start | H2 | `The setup helper is on this Mac, but it wouldn't start just now, so I won't guess.` |
| Unreadable response | H2 | `I can't read what's already on this Mac right now, so I won't guess.` |
| Versions don't match | H2 | `Control Tower and your setup are on different versions right now, so I won't guess. An update should line them back up.` |
| Can't confirm it's safe (fails closed) | H2 | `I can't confirm your setup is safe right now, so I'm holding off rather than guess.` |
| Unmapped CLI stop | H2 | `Something stopped me from reading your setup, so I won't guess.` |
| Your own space isn't recognized | H4 | `One of your own spaces on GitHub is set up in a way I don't recognize, so I left it exactly as it is.` |
| This Mac already has its own key | H4 | `This Mac already has a GitHub connection I didn't set up, so I left it exactly as it is.` |
| Settings here weren't set up by me | H4 | `I found settings on this Mac that I didn't set up, so I left them alone.` |
| Your unsaved work is in the way | H4 | `Some of your own unsaved work is in the way of an update, so I left it alone.` |
| A GitHub space couldn't be confirmed | H3 | `GitHub didn't confirm one of your own spaces, so I stopped before changing anything.` |
| This Mac's key couldn't be set up | H3 | `I couldn't give this Mac its own key, so I stopped. Nothing that was already here was changed.` |
| Codex Copilot didn't finish | H3 | `I couldn't finish adding Codex Copilot on this Mac.` (+ ` Everything else finished.` only when materialize did not block) |
| Setting up didn't finish | H3 | `Setting things up on this Mac didn't finish. Nothing that was already here was changed.` |
| Couldn't confirm everything is current | H3, title `I couldn't confirm everything's current` | the tray's own per-status sentence (§1.1), verbatim |
| Offline | H5 | `I can't reach the network right now, so I've paused. Nothing was changed, and I'll carry on as soon as you're back.` |
| Something else is updating | H5 | `Your setup is already being updated by something else, so I stepped back rather than get in the way.` |
| Organization setup unreadable | H6 | `I couldn't read your organization's setup from GitHub, so I've paused. There's nothing for you to do.` |
| Organization sign-in not set up | H6 | `Your organization hasn't finished setting up sign-in yet. There's nothing for you to do.` |
| Shared store not ready | H6 | `Your organization's shared store isn't ready for this Mac yet. There's nothing for you to do.` |

**H4 only:** the card `What I left alone` (one row per CLI review item, the CLI's own detail verbatim), the caption `Nothing was changed, moved, or removed.`, and the confirmation state after `Keep what I have`: title `Kept as it is`, intro `I left it exactly as it was. Control Tower keeps watch from the menu bar and picks this up if it ever changes.`

**Actions.** `Try again` (primary: H2, H3, H5) · `Check again` (H1, H4, H6; nothing failed, so "try" would overstate it) · `Continue in the menu bar` (all six; never marks setup complete) · `Show me how to install it` (primary: H1) · `Keep what I have` (primary: H4) · `Let setup manage it` (H4, only when the CLI declares consent for that gate) · `Include what I already have` (H4, existing return path). On a repeat of the identical hold, add one caption: `Still the same. Nothing changed.`

**A CLI-authored message is never a headline.** It appears under `What setup found:` (when the CLI wrote it for a person) or only inside the support details (when it names machinery). It is never concatenated into an app sentence.
```

### 6.2 Insert after the replaced §2.9:

```markdown
### 2.9.1 Details for support (collapsed, on H2 / H3 / H4 / H6)

- Disclosure label: `Details for support` (collapsed by default, never self-expanding)
- Expanded caption: `Send this to whoever looks after your Mac. It has nothing private in it.`
- Copy affordance: `Copy details` / confirmed `Copied`
- Block, one label per line, technical terms correct and expected here: `Copilot Control Tower <version> (<build>)` · `Setup helper: <path>` · `Report format: <schema_version>` · `Step: <stage id>` · `Result: <result>` · `Code: <error code>` · `Message: <verbatim>` · `Recorded: <yyyy-MM-dd HH:mm>`
- Omit any line the app cannot fill. Never print `unknown`. `Recorded:` is the product's one sanctioned timestamp, because it is a past fact for IT, not a promise to the user.

### 2.9.2 Installing the setup helper (the sheet behind H1's primary)

- Title: `Installing the setup helper`
- Intro: `This is one command for whoever set up this Mac. If that's you, paste it into Terminal. If it isn't, copy it and send it to them.`
- Block label: `The steps` (the documented install commands, mono block, never wrapped into prose)
- Copy affordance: `Copy these steps` / confirmed `Copied`
- Secondary: `Open the install guide ›`
- Primary: `Done` (closes the sheet and re-checks once, automatically)
- The H1 body itself never contains a command, a path, or the CLI's name.
```

### 6.3 Add one row to §1.2 (after line 84)

```markdown
| `not_installed` (**new**) | `The setup helper isn't installed on this Mac yet.` |
```

Rationale for the deck note: `.notFound` is currently folded into `io_error` in `native/render-state.swift:116`, so the tray tells a first-launch user "I can't reach your setup" about a thing that was never installed. Same misdiagnosis this change removes from the wizard. Needs a `not_installed` reason token to be renderable honestly. Flag to WS-A alongside the `hold` / `consent` additions.

### 6.4 The dead "entitlement" variant: **cut**

Delete `entitlement: This department isn't available to you anymore, so setup can't finish it.` from §2.9. It has no call site and cannot acquire one: a revoked entitlement is handled inline on the Departments row (`native/wizard.swift:804-807`, `.notEntitled` renders `Isn't available to you anymore.`) and never reaches `.holding`. The live copy for that case already lives in §1.5 (`<Department> isn't available to you anymore.`) and §2.4 (`Not available to you`). Keeping a Holding variant for it would mean maintaining a string that can only ever be wrong about where the user is.

---

## 7. Implementation notes

- **Character budgets:** eyebrow ≤ 30, title ≤ 50 (longest above is 42), intro ≤ 200 across at most two sentences, button ≤ 24. German and French run 30 to 35 percent longer; the footer must wrap rather than truncate.
- **No fragment assembly.** Each intro is one whole localizable string. The only sanctioned conditional appends are the codex-plugin ` Everything else finished.` clause and the materialize held-count sentence, and each is its own complete string, not a fragment.
- **Never localize CLI-authored text.** Framed CLI details and everything in the support block pass through verbatim, in whatever language the CLI emitted.
- **Pluralization** uses the two explicit forms in §3.2, not `\(n) thing(s)`.
- **VoiceOver:** focus moves to the title on entering Holding. The variant's tint is decorative; the eyebrow carries the meaning in text, so a grayscale or color-blind user loses nothing.
- **Reduce Motion:** the H4 body-to-confirmation swap cross-fades, no slide.
- **Never** offer a way past `.missingSecurityField`, and never render a button that would need `--skip-verify` or `--force` to work.
