# The connect experience: Bob's journey to his team's shared keys

| | |
|---|---|
| **Status** | **DRAFT FOR ALIGNMENT.** A design walkthrough, not a plan. It contains no tasks, no contracts, and no code. Every capability it implies that does not exist today is marked **[NEW]**. |
| **Decision it serves** | The G-6 fork logged in the forensic trace (`.copilot/wp/395.md` §c): option (a) admin-provisioned per-machine credentials, or option (b) the ratified team-gated model where membership *is* access. The trace's own sequencing note says this fork must be decided before anything is built, because option (b) deletes most of what option (a) requires. This document exists so the owner decides it on **felt experience and operational burden**, not on plumbing. |
| **Evidence base** | `.copilot/wp/395.md` (read in full: today's broken path, D-1..D-9, G-1..G-12) · `docs/05-security/credentials-and-boundary.md` §1.4, §1.5, §1.6.1 to §1.6.6 (RATIFIED) · RD-1 ("never distribute the org-wide credential") · `docs/03-design/control-tower-copy-deck.md` (the Quiet Instrument voice, Appendix A/B) · `native/wizard.swift` (the shipped step 6, the Set up stage labels, the Done card) · `CLAUDE.md` invariants #1, #3, #4, #5, #6. |
| **Voice** | Every quoted string here is drafted in the copy deck's register and obeys its hard rules: no em-dashes, no time estimates, no celebration, never a raw error, always names who owns the fix. Per invariant #1 these are **CLI-authored** sentences the app renders verbatim; they are drafted here so the owner can hear the experience, not so the app can hardcode them. |
| **Step numbering** | The shipped wizard reads `Step 6 of 9` (`wizard.swift:4575`); the copy deck says ten. This document uses the shipped numbering and does not resolve the discrepancy. |

---

## 0. Reframe: Bob is not connecting to anything

The brief says "Bob connects to his organization's shared credential store." That sentence contains the defect. It casts a **backstage fact** as a **frontstage task**, and everything broken in today's experience follows from that one casting error: a screen called "Your connections," a card called "Available to connect," a promised "Connect button," a setup stage announced to Bob as "Connecting your organization's shared store," and a terminal Done card that tells an accountant to check back later on a thing he has never heard of and could never have influenced.

Bob has no job to be done with a credential store. His job is:

> **When my department's tools need a key I don't have and shouldn't have, I want the work to just run, so I can close the month without asking a colleague to DM me something I know I'm not supposed to have.**

Read that job honestly and the design target inverts. **The ideal number of times the word "connect" appears on Bob's screen is zero.** Success is not a well-designed Connect button; success is that Bob finishes setup, does his budget work, and could not describe how any of it happened if you asked him. The store is plumbing. Plumbing that announces itself has failed, whatever its uptime.

The assumption I am challenging explicitly: **that a "needs-connect" state is a legitimate state for a shared thing to be in on a member's screen.** A shared connection has exactly two honest states from Bob's side. It is **ready**, because he is on the team, or it is **not his team's yet**, in which case the actor is his admin and there is nothing for Bob to press. The third state today's product renders, *yours but not connected*, is the one that turned into a dead end, and it exists only because the credential model made membership and access two different facts. Option (b) deletes the state. Option (a) has to design around it.

---

## 1. Current state, in one honest paragraph

The trace is the evidence; I will not restate it. What matters for design is how it *lands*. On a fresh Mac, step 6 promises Bob a working Connect button that exists nowhere in the codebase, then renders one of three dead ends depending on how far his machine got, the worst of which is raw developer stderr instructing a non-technical accountant to set two named credentials "in your .env." The one row he would ever be told to connect is `infisical`, which is structurally impossible to connect and reads `needs-connect` even on the owner's fully working machine (G-1). The setup stage whose job is to connect the store can only succeed on a machine that is already connected. Setup then declares success anyway, because that stage is the single one exempted from the completion rule, and hands Bob a "Still to do" card whose only instruction is to check again later, which re-runs the same failing call forever. Nothing names a human. Nothing can be pressed. The only mechanically correct action in the entire ecosystem is a Terminal command nobody is ever given, and the only credential that exists to hand him is the org-wide one RD-1 forbids distributing.

**The emotional shape of that:** mild dread on install (another IT thing that will eat the afternoon), genuine relief at step 2 (a code and a browser, that was all), then at step 6 a specific and corrosive feeling I would name **"the form that isn't for me"** — text about credentials, a heading that implies an action, and no action. Not frustration. Something quieter and worse: the belief that he has already done this wrong and shouldn't ask, because the screen is speaking a language that tells him he is not the intended reader. By the Done card that has hardened into **learned helplessness with a receipt**: he was told there is something still to do, and told nothing he can do about it. Bob's next move is a DM to a colleague asking for "the key," which is exactly the behavior the security model exists to prevent. **Today's design manufactures the risk it was built to remove.**

### The forces acting on him

| Force | What it actually is for Bob |
|---|---|
| **Push** | Asking a colleague in team chat for "the NetSuite key," waiting a day, feeling like a nuisance, and half-knowing he shouldn't be holding it. |
| **Pull** | The work runs on day one and he never has to ask anyone for anything. |
| **Anxiety** | That he will be handed something he can break, or be the person a leak gets traced back to. Every credential surface feeds this force; every absent one starves it. |
| **Habit** | Ask a person. Keep the key in a note. Both survive any product that makes the official path feel like a form he is failing. |

**The design consequence:** the strongest available move on all four forces at once is to **remove the credential from Bob's experience entirely**, which is what option (b) does structurally and option (a) can only approximate.

### The transition that breaks, not the screen

Step 6 asks about his org's connections **before** step 8 has brought his org's configuration onto the Mac. That ordering produces the trace's second dead end all on its own: the store is not unreachable and Bob is not unauthorized, the machine simply does not know yet where the store is, and the screen reports that in machinery language as though it were a fault. **This is a sequencing defect, not a copy defect,** and it is worth naming separately because it will survive any credential model. A screen that reports on a thing that has not been set up yet can only ever say something untrue or something confusing. Either step 6 moves after materialization, or it must speak only about what is knowable at that moment.

---

## 2. Three framings, and why the fork is not what it looks like

| # | How might we... | Desirable | Feasible | Viable |
|---|---|---|---|---|
| **HMW-1** | ...give Bob a working Connect button, so the promise the screen already makes becomes true? | **Low.** It asks a non-technical person to act on a decision he cannot judge, on a schedule he does not control. A button that means "wait for a human" is a button-shaped delay. | **Medium.** Needs credential minting, a delivery path, and a keychain writer (G-4, G-5, G-6a). | **Low.** Every member, every Mac, forever, plus a support ticket each time it stalls. And it builds the pipeline the ratified design intends to delete. |
| **HMW-2** | ...make being on the team *be* the access, so there is nothing to connect? | **High.** Bob's step 2 sign-in becomes the whole credential story. Step 6 has no "Available to connect" card because the state cannot occur. | **Low to Medium.** The store must answer to the same sign-in as GitHub (D-1, G-12). No new user-facing machinery at all, which is the point. | **High.** One grant lever, one revoke lever, zero per-person admin work, and offboarding actually revokes. |
| **HMW-3** | ...make the *absence* of a connection completely legible and correctly routed, so nobody is ever stuck, whatever the credential model is? | **Medium.** It makes nothing new work. It removes every dead end. | **High.** Copy and routing only (G-1, G-2, G-3). | **High.** |

**Convergence.** HMW-2 is the North Star and §3 walks it. HMW-1, disciplined into an admin-owned approval rather than a Bob-owned chore, is the pragmatic first release and §4 walks it.

**The finding that matters most here:** HMW-3 is not a third option. It is the **floor underneath both**, and it is the only part of this document that is unblocked by the owner's decision. Whichever credential model wins, Bob's Mac will one day be offline, or the store will be down, or he will have been removed from a team, and on that day the product must say a true sentence that names a human. Today it says raw stderr or nothing. **Fix the floor first; it cannot be wasted work under either answer.**

**Rejection rationale, stated plainly.** HMW-1 as literally briefed is rejected as a *destination* and accepted only as a *bridge*: it fails the desirability test at the exact moment it matters (day one, new hire, admin in a meeting), and its viability cost is permanent while its benefit is temporary. HMW-3 is rejected as an *answer* because honesty about a broken thing is not the same as the thing working; Bob who is told clearly that his keys are unavailable still cannot close the month.

---

## 3. North Star walkthrough: membership is access (option b)

### Day zero, which Bob never sees

Bob's admin, months before Bob is hired, stands up the org. On the "Your shared secret store" screen she pastes a web address and names the teams that can use it. The screen educates in the copy deck's existing words, and it carries one new line **[NEW]**:

> **Who can use it:** `Use the same sign-in your team already uses for GitHub, so being on a team is what hands out the keys. Nobody has to be sent a key, ever.`

Control Tower then does something the current design does not: it **proves the claim before it makes it [NEW]**. It checks that the store really does hand out keys by team membership, and only then says so.

> `Connected. Anyone on the teams you named gets these keys automatically.`

And when it cannot prove it, the never-fake-healthy rule applies to the admin exactly as it applies to Bob:

> `I couldn't confirm this store hands out keys by team, so I won't say it's connected.`

The day Bob is hired, his admin does exactly one thing: she adds him to the **Accounting** team on GitHub. That is the entire provisioning event. There is no second system, no queue, no message to send, no credential in existence anywhere with Bob's name on it. **The single most important property of this model is that the admin's to-do list has one item on it and always will.**

### Day one, in Bob's own terms

He drags the app to Applications because that is the only Mac install he has ever understood. Welcome. Then a screen asks him to sign in to GitHub and shows him an eight-character code; he pastes it into a browser tab, clicks the green button, and the wizard moves on by itself. He notices, faintly, that nothing asked him to make a decision. Detect. A screen that tells him what he is getting, in the names of things rather than the names of systems. Departments: **Accounting** with a `Join` button, which he presses, because it is obviously his.

Then step 6, and in the North Star it is not a form. It is a **receipt**.

> **Step 6 of 9** · `What your team has set up for you`
> `Some of these were set up by your team, so they are already working for you. The rest use your own accounts, so they need your sign-in.`
>
> **Shared with your team** · `Ready for you. Nothing to sign into.`
> `NetSuite` ....................... `Ready`
> `The department's research assistant` ..... `Ready`
>
> **Your accounts**
> `Slack` ..... `Needs sign-in` · **[ Sign in ]**

What Bob can do here: sign in to Slack, which is genuinely his own account, and press Continue. That is the whole action set. **No shared row ever carries a button**, which is not a limitation but the load-bearing message of the screen: things with his team's name on them are not his to operate.

What he feels is not delight. It is **recognition**, and recognition is the correct target. The screen knows he is in accounting. It names NetSuite, which he uses daily, rather than naming a credential he has never heard of. The absence of a button where he expected a chore is the single best moment in the flow, and it works precisely because nothing draws attention to it.

Steps 7 and 8 pass without incident. The setup stage formerly announced as "Connecting your organization's shared store" is no longer a connection event, because there is nothing to connect; it becomes a check, phrased as `Getting your team's shared keys ready`, and **[NEW]** it stops being the one stage exempted from the completion rule, because a stage that can now genuinely succeed must be allowed to genuinely fail.

Step 9:

> `You're set up.`
> `Control Tower now lives quietly in your menu bar. When it has nothing to say, it says nothing. That quiet icon means everything's current.`

**There is no "Still to do" card.** The entire content of the North Star's success state is its absence.

### The first real use, which is the whole point

Thursday. Bob asks his copilot to pull last month's close from NetSuite and sanity-check three variances. It answers. Somewhere behind that, a skill declared it needed a key by name, the CLI asked the store for it using the fact that Bob is on the Accounting team, the store checked that fact against the same sign-in Bob used on day one, handed back a value that existed for the lifetime of one process, and nothing was written anywhere. Bob experienced none of this. **He never learns the word Infisical. He never learns the word credential.** If you asked him how his copilot reaches NetSuite he would say "it just does," and that answer is this design's highest possible score.

### When it breaks, which it will

**The store is unreachable.** Not Bob's fault, not Bob's fix, and critically **not Bob's task**. The shared rows go quiet rather than red, and one notice appears in his lane:

> `Your team's shared connections can't be reached right now. Nothing on this Mac changed, and I'll keep checking.`

The named next actor is Control Tower itself, and it says so, which is what makes this not a "check again later" dead end. If it persists past the point where waiting is still a plausible answer, the sentence changes and hands off to a human, reusing the shipped `Copy details for support` affordance rather than inventing a channel:

> `Your team's shared connections still aren't reachable, so this one belongs to whoever looks after your Mac.` · **[ Copy details for support ]**

**He was removed from the team.** Technically this is one status code away from the outage above, and today's product would render them identically. **They are different human situations with different next actors and they must never share a sentence [NEW].** Removal reads:

> `Your access to your team's shared connections was turned off. Anything you saved on this Mac is still yours, and nothing was removed.`
> `If that's a surprise, ask whoever looks after Accounting.`

The second line does the real work. Bob's instinctive read of any access loss is that he is in trouble; the copy's job is to defuse that in one line, name the human, and offer him nothing to press, because pressing would imply he could argue with it.

**A service his org hasn't made available.** A colleague mentions the Salesforce thing works for Sales. Bob looks. He must not find silence (which reads as a bug) and must not find a Connect button (which reads as a promise):

> `Salesforce` ..... `Your team hasn't made this available to you.`
> `Whoever looks after Accounting can add it.` · **[ Copy a note to your admin ]** **[NEW]**

That affordance composes plain text he can paste into chat. It invents no request-tracking system, adds no admin queue, and converts the only genuine dead end left in the model into a routed handoff.

### Offboarding, which has to actually revoke

Bob leaves. His admin removes him from the Accounting team on GitHub, exactly as the governance screen already instructs, and rotates anything genuinely exposed. **That single removal revokes his store access too, because it was never two facts.** On Bob's Mac, at the next invocation, the shared rows stop resolving and he sees the removal notice above. The product does not pretend more than it did: content already on his disk is not remotely wiped, that is the accepted residual, and the copy never implies otherwise. **This is the paragraph that makes option (b) a security answer and not only a UX one:** in every other model, revocation is a second action someone has to remember.

---

## 4. Pragmatic first release: the approval, designed properly (option a)

If the store cannot be made to answer to the org's sign-in in the first release, a Connect moment exists. Then it must be **designed as an admin-owned approval that Bob merely initiates**, never as a credential task Bob owns.

### The routing rule comes first

Bob is shown this **only if he can act**, which here means only if his org has turned on approvals. The CLI decides that and says so **[NEW]**; the app renders the decision (invariant #1, invariant #5). If approvals are off, Bob never sees a request affordance; he sees §3's "your team hasn't made this available" sentence and the escalation routes away from him entirely. **A request button in an org that cannot receive requests is the same defect as today's Connect button, rebuilt.**

### The moment, on Bob's screen

Step 6 gains exactly one row, and it does not say Connect, because "connect" does not describe what pressing it does:

> **Available to your team**
> `Your team's shared connections` ..... `Needs one approval from your admin` · **[ Ask for access ]**

Pressing it opens a sheet that deliberately rhymes with the GitHub sign-in he completed four minutes earlier, because reusing a familiar shape is worth more than any explanation:

> `Ask for access`
> `Read this code to whoever set up Copilot for your team. When they approve it, your team's shared connections arrive here on their own. You'll never have to type a key.`
> **Your code** · `4TQ9-KMD2` · **[ Copy code ]**
> `Waiting for your admin to approve...`

The code is **not a secret**. Reading it aloud across an open-plan office grants nobody anything, because it only names a pending request that still requires the admin's own authenticated approval. That property is what lets it travel through a human channel at all, and it should be stated to the admin, never to Bob, who does not need to carry the reasoning.

If Bob closes the wizard, the request survives and moves to his menu bar. When it lands, the reward is silence plus one past-tense line in `What changed`: `Your team's shared connections are ready.`

### The admin's counterpart

Two shapes, both native to this product:

- **Admin mode gains a governance panel [NEW]:** `Requests for access`, one row per pending request, showing who asked, from which Mac, and the code they will read to her. `Bob Alvarez (Accounting) asked from a Mac named "Bob's MacBook Air". Code 4TQ9.` · **[ Approve ]** **[ Not now ]**. On approve: `Approved. Bob's Mac picks this up on its own. You never have to send him a key.` And the RD-1 property, in her language: `This gives that one Mac its own key, which you can turn off later without changing anyone else's.`
- **For orgs without Admin mode:** the same handoff pattern the product already uses twice, a copyable command run through Claude Code, exactly as "Connect the shared store" works today. This is not a downgrade; it is the house's existing baton pass.

### How the credential lands without Bob ever seeing one

The human channel carries the code. **The credential itself never touches it.** Approval mints a scoped, revocable, per-machine identity **[NEW]** and the CLI on Bob's Mac, which has been holding the code as its claim ticket, receives it once and writes it straight into his keychain **[NEW]**. Bob's screen only ever changes *state*. It never shows a value, never a masked value, never the first four characters. On screen, the row simply becomes:

> `Your team's shared connections` ..... `Ready`

and the "Available to your team" heading disappears entirely, because nothing under it is pending any more.

### Degraded but honest

| Situation | What Bob sees | Who acts next |
|---|---|---|
| Admin hasn't approved yet, and it has stopped being plausible that she is about to | `Your request is still waiting on whoever looks after Accounting.` · **[ Copy details for support ]** | Named human, not a timer |
| Approved, but his Mac was asleep or offline | `Your access was approved. I'll finish setting it up when you're back online.` | Control Tower, and it says so |
| Declined | `That request wasn't approved. Whoever looks after Accounting can tell you why.` No retry button, because a retry that re-fails is a slot machine | The admin |
| Bob isn't actually on the team | The §3 "your team hasn't made this available to you" sentence, **not** a decline. Different situation, different sentence | The admin, off Bob's screen |
| He has two Macs | `Each of your Macs asks for its own access. This one is asking now.` Said once, or he reads the second ask as a bug | Bob, once per Mac, by design |
| Store is down at approval time | The **same** outage vocabulary as §3. Never invent a second dialect for the same fact | Control Tower, then IT |

---

## 5. The experiential delta, for the fork

| | **Option (b), membership is access** | **Option (a), approval and claim code** |
|---|---|---|
| **Bob's day one** | Zero credential moments. He signs in to GitHub once, at step 2, and never meets the subject again. | One moment, well designed, that ends in **waiting on another human before his first run is complete**. Worst on the exact day it is most likely: new hire, admin in back-to-back meetings. |
| **What Bob learns** | Nothing. He cannot describe the mechanism and never needs to. | That there is a thing called shared access, that his admin controls it, and that he had to ask. Small, but it moves him from "it works" to "someone lets me." |
| **Bob's failure surface** | Two states, both routed: unreachable, or turned off. | Six states, all needing copy: pending, stale-pending, declined, approved-but-undelivered, not-on-team, plus both of (b)'s. |
| **The admin's grant** | One act, forever: add to the GitHub team. | One act **per person per Mac**, forever, plus a queue she must notice. Her attention becomes a dependency in Bob's first run. |
| **The admin's revoke** | The **same** act as the grant. Removing the team membership revokes store access, so offboarding cannot be half-done. | Two acts in two systems. Remove from GitHub, then remember to revoke a per-machine key. Offboarding is only as good as her memory, which is how the G-12 gap survives. |
| **What the org must have** | A store that answers to the same sign-in as GitHub. Real setup cost, one time, and a real blocker for orgs that cannot do it. | Nothing extra, which is exactly why it is tempting. |
| **Lifespan** | Terminal. This is the ratified design. | A **bridge with a deletion date**. When (b) lands, this surface is retired and Bob's experience silently improves, but the delivery pipeline built for it is discarded, which is precisely the waste the trace's sequencing note warns about. |

---

## 6. Journey map

Legend: **B** = Bob · **A** = admin/owner · **CT** = Control Tower + CLI, acting on its own. Invariants per `CLAUDE.md`.

### North Star (option b)

| Stage | Bob sees / feels | Actor | System behavior | Invariant honored |
|---|---|---|---|---|
| Day zero, store stood up | Nothing. He does not exist yet | A | Store address inherited through org config; access bound to team membership; CT refuses to say "connected" until it can prove it | #4 posture inherited, #6 endpoint is not a secret |
| Day zero, Bob hired | Nothing | A | One team membership added. No credential is created anywhere | #6 no cross-tier write, RD-1 |
| Install to step 2 | Mild dread, then surprise at how little was asked | B, once | GitHub sign-in by code; result to keychain | #6 secrets never in git |
| Steps 3 to 5 | Orientation. Recognition of his own department | B | Detect and join, no credential surface at all | #5 only his own decisions |
| **Step 6** | **Recognition, and the relief of an expected chore that isn't there** | none | Shared rows read `Ready`, no button ever; personal rows carry his own sign-ins | #1 CT renders, CLI computes; #5 |
| Step 8 | A named phase, no clock | CT | Shared keys verified rather than connected; no longer exempt from the completion rule **[NEW]** | #1, never-fake-healthy |
| Step 9 | `You're set up.` and then silence | none | No "Still to do" card exists in this model | never-fake-healthy |
| First real use | Nothing at all. The absence is the experience | CT | Key resolved per invocation from the store on his own membership, nothing cached to disk | #6 |
| Store unreachable | `can't be reached right now... I'll keep checking`, then a named human | CT, then IT | Honest degrade, never red, never a button, never stderr | #1 CLI authors the sentence, #5 |
| Removed from team | `Your access here was turned off. Anything you saved is still yours` | A caused it, B told | 403 and 503 are **different states with different sentences** **[NEW]** | #3 never-destroy, #5 |
| Service not made available | `Your team hasn't made this available to you.` plus a named human | A | Optional note-to-admin composer **[NEW]**, no request system invented | #5 escalate what he can't action |
| Offboarding | The removal notice, once | A | One removal revokes both. Local content untouched and not claimed otherwise | RD-1, #3 |

### Where option (a) diverges

| Stage | Bob sees / feels | Actor | System behavior | Invariant honored |
|---|---|---|---|---|
| Step 6 | One row he *can* act on, and the small deflation of being blocked on a person | B initiates | Row shown **only** when the CLI reports the request is actionable by him **[NEW]** | #1, #5 |
| The ask | A code sheet that rhymes with day one's sign-in | B reads a code aloud | Code is non-secret and single-use; it names a request, it grants nothing | #6 secrets never travel a human channel |
| The approval | Nothing, unless he is watching | **A** | Scoped, revocable, per-machine identity minted **[NEW]**; machine to machine delivery straight to keychain **[NEW]** | RD-1, #6 |
| Landing | A row flips to `Ready`. No value, no confirmation theater | CT | Never displays, masks, or echoes a credential | #6 |
| Stale or declined | A true sentence naming his admin, never an infinite retry | A | No auto-retry loop, no "check again later" without an owner | #5 |
| Offboarding | Same notice as (b) | A, **twice** | Team removal **plus** a separate key revocation. The gap is operational, and it is the honest price of this option | RD-1 partially, #5 |

---

## 7. Non-goals and anti-patterns, carried from the trace

1. **No raw error text, ever, on any Bob surface.** Not stderr, not an exit code, not a reason token. The CLI authors a sentence for a person or the app says nothing (invariant #1). This is the G-2 rule and it applies to the admin's screens too.
2. **No dotfile, Terminal, or file-path advice as a user-facing step.** Not `.env`, not Keychain Access, not a `security` command. If the only real fix is a command, it belongs behind the existing "show me the step" sheet pattern and only for someone the product can prove is the admin.
3. **No secret value on screen, in any form.** Not masked, not truncated, not "the last four," not in a copy button. **And no secret *names* either.** `INFISICAL_CLIENT_ID` is as unreadable to Bob as the value it holds. Name the service, never the key.
4. **No state whose only action is impossible.** G-1's permanent false negative is not merely a bug; it is the anti-pattern in its purest form. If a row cannot be acted on by the person reading it, it must not be styled as an action.
5. **No "check again later" without a named next actor.** Either Control Tower says it will keep checking, in its own voice, or a human is named. Never the user, alone, in a loop.
6. **No promise the next card contradicts.** Step 6 currently guarantees "a working Connect button," and the following card withdraws it. Either the affordance exists or the sentence goes. This is the honesty violation that matters most, because it is the one Bob can personally verify.
7. **No button on a shared row.** A thing his team set up is not his to operate, and the absence of the button is how he learns that without being told.
8. **No stage that is exempt from the completion rule while setup still claims success.** A stage that cannot fail cannot be trusted when it passes.
9. **Two situations with different next actors never share a sentence.** Unreachable is not removed. Declined is not ineligible. Collapsing them saves one string and costs the user the only thing the screen was for.
10. **Bob is never asked to judge a security event, and never blamed for one.** Access loss is stated as a fact about access, with his own work explicitly preserved in the same breath.
11. **No celebration, no time estimate, no percentage.** Silence is the success state, and the strongest version of this whole design is a Done screen with nothing extra on it.

---

## 8. The one question the owner has to answer

Everything else in this document follows from a single fork, and the fork is not technical:

> **Is "your organization's shared store must answer to the same sign-in as your GitHub teams" a product requirement, or a recommended configuration with a supported fallback?**

Answer **requirement**, and §3 is the design: no Connect moment ever exists, the admin's list has one item on it forever, offboarding cannot be half-done, and the cost is that an org which cannot wire its store that way is not supported on shared connections at all.

Answer **recommended, with a fallback**, and §4 ships alongside it: Bob gets one well-designed moment that still blocks his first run on another person, the admin inherits a permanent approval queue and a two-system offboarding discipline, and the product carries a bridge it intends to delete.

Two things are worth putting beside that question. First, the sharpener: **is there a real member who needs shared connections before the store can be team-gated?** If the honest answer is no, option (a) is a pipeline built for nobody. Second, the part that needs no answer: **§7 and the honest-degrade floor from HMW-3 are correct under either branch and are not blocked by this decision.** Today's screen tells an accountant to edit a dotfile. That is worth fixing this week regardless of which way the fork goes.

---

## Appendix: capabilities marked [NEW]

Grouped for legibility, not as a plan. Each is a capability the walkthroughs imply and today's product does not have.

**Floor, needed under both answers:** CLI-authored plain-language sentences for every store state, never stderr · unreachable and revoked as distinguishable states with distinct copy and distinct actors · the step 6 promise either made true or withdrawn · rows that cannot be acted on rendered as facts, never as actions · a named human or a stated self-retry on every terminal state.

**North Star (b):** store authorization bound to the org's own sign-in and GitHub team membership · admin-side proof before "Connected" is claimed · a real answer for which teams get which keys · the shared-keys setup stage promoted out of its completion-rule exemption · optional note-to-admin composer for an unavailable service.

**Pragmatic (a), additionally:** scoped, revocable, per-machine identity provisioning · a non-secret single-use claim code and its approve channel · machine-to-machine delivery writing straight to the keychain · a CLI-computed "this is actionable by you" signal so the affordance is routed, not universal · an admin Requests panel, or the copyable-command handoff for orgs without Admin mode · pending requests that survive the wizard and resume in the menu bar.
