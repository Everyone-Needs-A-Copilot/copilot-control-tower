# Credentials Carrier & the Personal↔Shared Leakage Wall

| | |
|---|---|
| **STATUS** | **RATIFIED 2026-07-07 (owner).** Promoted from `docs/01-architecture/proposals/credentials-and-boundary.md` (DRAFT PROPOSAL). This is now the canonical security design for the two open foundational problems logged in [`SOUL.md`](../../SOUL.md) §9 ("credentials-carrier problem," "writable-tier vs never-destroy tension" as it bears on leakage) and `interview-ground-truth.md` §10. |
| **Author** | Security engineering pass (STRIDE + DREAD) |
| **Scope** | Problem 3 (credentials carrier) and Problem 4 (personal↔shared leakage wall) only. Does **not** resolve the third open problem (writable-tier vs never-destroy tension) or the merge-conflict UX — those remain separate, unresolved. |
| **Reads on** | `CLAUDE.md` invariants (esp. #4), `architecture.md` §6–§9, `cli-contract.md`, `four-tier-topology.md` §6, §8–9, this doc's sibling `security-and-trust.md` (stub — updated to point here). |
| **Governing rule for this whole document** | Invariant #1 (parse, never compute) applies to security architecture exactly as it applies to health status: **Control Tower renders and invokes; it never holds a secret, a credential decision, or a trust root.** Every mechanism below is placed in the CLI/ecosystem layer, the MDM-managed domain, or (rarely) a third-party authoring tool — never in the app. |
| **Carried-forward open seam** | The **author git-push-credential provisioning** mechanism (how `ssh-personal`/`ssh-work` SSH keys are actually generated, distributed to, and rotated on an author's machine) is specified only **in principle** — it leans on the four-tier SSH-alias *model* (`four-tier-topology.md` §6.1) without a fully worked provisioning mechanism. This is distinct from Problem 3 (integration secrets, fully specified below) and is flagged as an **explicit open follow-up requiring a worked design before implementation.** See §6. |

---

## 0. Problem framing — and where invariant #4 bites

Both problems are instances of the same question invariant #4 already answers in the abstract but does not yet answer *concretely*: **"security-sensitive state must be inherited and enforced, never weakened, and honored only from a trusted, forced domain — never from user-editable config or content."** Two things in this product are currently unplaced against that rule:

- **Secrets** (API keys, integration tokens) are exactly the kind of security-sensitive state invariant #4 was written to protect — but no document yet says *where they live*. The owner's own worry ("do we put it in GitHub?") is the tension made explicit: GitHub is the one carrier this whole product already trusts for *everything else* (code, skills, knowledge, MCP declarations), so it is the obvious-looking answer — and it is precisely the wrong one, because git is a distribution and history mechanism, not a trust boundary, and invariant #4 requires a **forced, machine-scoped, revocable** carrier, which git structurally cannot be (see §2.4).
- **Personal-tier content** must never reach a shared/public remote. This is not new: SOUL.md §4 already names it as *The Leak* and states the line in the sand in prose ("separate trees with separate remotes; the push path is tier-scoped and fails closed"). What is missing is the **mechanism** that makes that prose true — the STRIDE analysis and the structural guarantees below are that mechanism, not a new rule.

Both problems share one root cause worth naming up front: **the four-tier model already solved a structurally identical problem for a different reason.** `four-tier-topology.md` §6.1 picked SSH host aliases to solve *multi-account git auth* (so one machine can authenticate as three identities against one hostname), and §6.2 picked *separate repos per department* to solve *read-confidentiality* (because GitHub has no path-level ACL). Both problems in this RFC are solved by **applying those same two decisions one tier further down** — to the personal↔shared boundary and to the secret/credential boundary — rather than inventing new machinery. That is the throughline of everything below.

---

## 1. Problem 3 — the credentials carrier

### 1.1 What "secrets" means here (scope clarification)

Two different things are easy to conflate and must be kept separate:

1. **Git-repo read/write auth** (which tier's repo a machine may clone, and which tier an author may push to) — the *model* is set by `four-tier-topology.md` §6.1 (SSH host aliases: `ssh-personal` / `ssh-work` / `anon` / `gh-app:<slug>`). **The model is settled; the provisioning mechanism for the push-capable aliases (`ssh-personal`/`ssh-work`) is not fully worked — see §6.** Not otherwise this RFC's problem.
2. **Integration secrets** — API keys/tokens for the things CLI Copilot's *skills and MCP servers* call on the user's behalf (an LLM provider key, a Slack bot token, a database credential, a CRM API key). **This is Problem 3.** These have nothing to do with which GitHub repo a machine can read; they are runtime credentials a *tool* needs when a skill executes.

### 1.2 Options considered

| Option | Mechanism | Verdict |
|---|---|---|
| **A — Secrets committed into a repo (any tier, public or private)** | A `.env`, `secrets.yml`, or `mcp.json` with inline keys, checked into personal/dept/org/foundation git. | **Rejected.** See DREAD in §1.3. This is the owner's "do we put it in GitHub?" question, pressure-tested and refuted. |
| **B — A dedicated cloud secret store (Vault, 1Password, AWS Secrets Manager, Doppler)** | Ecosystem fetches secrets from a managed secret-store API at runtime. | **Not assumable.** The owner's stated constraint is "a company has NO cloud secret store" — most target companies (3-person team → mid-size enterprise without a security team) do not run one. Cannot be the *only* path; may be an **optional enhancement** for enterprises that already have one (see §1.5), never the baseline. |
| **C — MDM-provisioned managed config carrying the secret value itself** | The `.mobileconfig`/managed-preferences payload contains the raw API key. | **Rejected as a general mechanism.** A `.mobileconfig` is push-once, hard to rotate centrally, is itself a file that can be exported/inspected on the endpoint (`profiles show`), and — most importantly — it would mean a security-sensitive *secret* travels through the *same* channel invariant #4 already reserves for **config values**, not secret material. Conflating "trusted channel" with "safe to carry raw secrets" is the anti-pattern. Narrow exception: MDM may provision a *machine credential* for unattended kiosk machines (§1.5), which is a different, bounded case. |
| **D — SSH host aliases extended to secrets** | Reuse the personal/work alias split for git auth, but that's an auth *selector*, not a secret *carrier* — SSH keys authenticate git operations, they don't hand a Slack token to a running skill. | **Solves a different problem (repo auth), not this one.** Kept as the mechanism for §1.2's item 1, irrelevant to item 2. Note: the *selector model* is settled but its provisioning mechanism is the open seam in §6. |
| **E — OS keychain + interactive per-integration authentication, secret never leaves the machine, inheritance content carries only a *reference*** | Each integration is authenticated **once, per machine, per user**, via that integration's own OAuth/device-code flow (or, for legacy key-only APIs, a one-time paste into a native secure-input field); the CLI writes the resulting token **directly to the OS keychain** (macOS Keychain / Windows Credential Manager) via the OS API; the ecosystem manifest/skill declares only `requires_secret: SLACK_BOT_TOKEN` (a name + acquisition method), never a value. | **Recommended — RATIFIED.** Validated below. |

### 1.3 Validating the hypothesis — DREAD on the rejected anti-pattern (Option A)

The task's strong hypothesis — *secrets never travel inside inheritance content or any git repo; GitHub is explicitly not a secret carrier* — is **confirmed**. Scoring the anti-pattern makes the rejection concrete rather than a taste call:

| Factor | Score (0–10) | Why |
|---|---|---|
| **D**amage potential | 9 | Any reader of the repo (which, for the department/org tier, can be dozens-to-thousands of employees, and for foundation is the entire public internet) gets a live, working credential — not a hint, the actual key. |
| **R**eproducibility | 10 | `git log -p`, `git blame`, or any of a dozen public secret-scanners find it every time, forever — including in "deleted" files, because git history retains blobs until a destructive rewrite. |
| **E**xploitability | 9 | Zero skill required: `grep -r "sk-" .git`. Automated scanners (GitHub's own secret-scanning, truffleHog) find it without an attacker even trying. |
| **A**ffected users | 8–10 (tier-dependent) | Personal tier: one person. Department/org tier: every current *and future* employee with repo read access. Foundation tier: the entire internet, permanently, the moment the PR merges. |
| **D**iscoverability | 10 | Foundation is public by definition. Private dept/org repos are discoverable by every teammate who ever clones, and by CI systems, IDE plugins, and any future employee onboarded with read access. |

**Average ≈ 9.2/10 — Critical, unconditional deploy blocker.** This is not a probabilistic risk to accept with mitigations; it is a certainty the moment the commit lands, and — per the project's own git-safety posture (destructive history rewrites are explicitly the kind of action this ecosystem avoids) — it is **not cleanly reversible** even after discovery. It is the exact same shape of harm as *The Leak* (SOUL.md §4): irreversible, and a wipe or rotation after the fact does not undo the exposure window. **GitHub, at any tier, public or private, is explicitly rejected as a secrets carrier.**

### 1.4 Recommended mechanism (Option E, detailed)

**Where the token lives:** the **OS keychain**, scoped **per-user** (matches the existing "per-user, not per-machine" rule in `architecture.md` §8.3), under a well-known service identifier (`com.enac.copilot.<integration>`), written via the platform's native secure-storage API (`Security.framework` on macOS; Credential Manager / DPAPI on Windows for the Phase-4 re-skin). The token **never** touches disk as a plaintext file, is **never** written into any directory a git working tree could pick up, and is **never** logged.

**How CLI Copilot reads it:** at skill/MCP-server invocation time, the CLI resolves `requires_secret: <NAME>` by a keychain lookup (`security find-generic-password` equivalent) and injects the resolved value into the spawned process's environment (or a short-lived socket handoff for MCP servers that support it) — the secret exists only for the lifetime of that one invocation's process tree, never in a config file the CLI writes back to a repo. If the lookup misses (never authenticated, or the token expired/was revoked), the CLI does **not** silently no-op or degrade the skill — it surfaces a `signed-out`-shaped finding via `doctor --json`, reusing the **existing** `Signed-out` state and badge already defined in `architecture.md` §2, rather than inventing a new status class.

**How non-technical Bob authenticates:** exactly the same GUI device-flow already specified for CLI Copilot's own sign-in in `architecture.md` §4 ("show 8-char code, open browser"), generalized to **every integration a skill needs**, not just the CLI's own auth. This is the single Bob-facing ask the Bob-agency model already permits (`architecture.md` §9, lane 3 — "the one sign-in approve"): Control Tower's popover surfaces "Sign in to Slack" as a plain sentence, opens the browser to the integration's own OAuth consent screen, and on success the CLI writes the resulting token to the keychain. Bob never sees a raw API key, never pastes anything into a text file, never touches YAML. For the minority of legacy integrations that only offer a static API key (no OAuth), the wizard presents a **native OS secure-input field** (not a plain text box, not a markdown file) that writes directly to the keychain via the CLI, with the "teach" step explicitly telling Bob never to paste it anywhere else (including Obsidian, Slack, or a chat window).

**Company with no cloud secret store (the owner's actual worry) — the explicit fallback:** the mechanism above **requires no dedicated secrets product at all.** It is satisfied by:
1. Each integration's **own OAuth/device-code endpoint** (Slack, Notion, an LLM provider, a CRM) — this is infrastructure every SaaS integration already ships for free; a company needs no Vault, no Okta, nothing purchased.
2. Where a company *does* have an identity provider it already pays for (Google Workspace, Microsoft 365, a GitHub org) — that IdP's own device-code flow can additionally gate a **machine-scoped, IT-issued** credential for shared/lab machines (§1.5), still landing in the per-user keychain, never in git.
3. For a company with genuinely nothing — no IdP, no per-integration OAuth support, a 3-person team — the fallback degrades gracefully to the **one-time secure-paste into the native keychain field** described above. It is manual and per-machine, but it is still **never git**, and it is still revocable at the source (rotate the key at the vendor; the old keychain entry simply stops working on next use, surfaced as `Signed-out`).

**What happens on a machine with no MDM:** identically to a managed machine. MDM changes **nothing** about the credential mechanism itself — the same per-user keychain + interactive OAuth/device-flow applies on a solo developer's unmanaged laptop exactly as it does on a fleet machine. MDM's *only* role in this picture (never a requirement for the mechanism to work) is:
- Optionally **forcing `AuthMode`** for shared/kiosk machines (already a defined managed key in `architecture.md` §8.3) to mandate a machine-credential path instead of an interactive per-user sign-in;
- Giving IT a **centralized revocation lever** (the IdP admin console, or the SaaS integration's own admin panel) that is faster than waiting for the client-side deprovision cadence — this is additive to, and reuses, the existing server-side-revocation-first deprovision pattern already specified in `architecture.md` §8.3 ("the real backstop is server-side token revocation").

Trust roots for *which* OAuth issuer/endpoint is trusted per integration remain **compiled-in code, not config** (invariant #4) — a user-domain or even a managed-domain preference cannot repoint an integration's OAuth endpoint; only a signed CLI release can add or change a trusted integration.

### 1.5 The one narrow MDM exception — kiosk/lab machines

`architecture.md` §8.3 already anticipates unattended, auto-login lab machines with **"a machine credential (`AuthMode=gh-app` token in the system keychain)."** This RFC extends the same shape to integration secrets: a kiosk machine may be issued a **least-privileged, IT-provisioned service-account token**, delivered by an MDM-triggered *bootstrap exchange* (the managed profile carries a one-time enrollment reference or short-lived bootstrap code — never the long-lived secret itself — which the CLI exchanges, once, for the real token via the integration's own token endpoint). This preserves "secrets never travel as content" even in the one case where no interactive human is present to complete a device flow. This path is narrow, opt-in per machine class, and does not change the default per-user mechanism above. (Depth of kiosk support remains an **open decision**, per `architecture.md` §11 item 3 / red-team B-H7 — this RFC does not resolve that, only ensures whatever ships there doesn't reopen the secrets-in-git anti-pattern.)

---

## 2. Problem 4 — the personal↔shared leakage wall

### 2.1 Trust boundaries (mapped before any code review, per methodology)

| Boundary | Contains | Readable by |
|---|---|---|
| **Personal tree** | one individual's personal-tier content | that individual only (private personal GitHub repo, `auth: ssh-personal`) |
| **Department tree** | one department's shared content | that department's team (private dept repo, `auth: ssh-work`) |
| **Org tree** | company-wide shared content | every org member (private org repo, `auth: ssh-work`, org base permission) |
| **Foundation tree** | the public framework | the entire internet (public repo, `auth: anon`) |
| **ENAC's own internal stack** | `enac-org-private` (never-public + not-yet-public content) | ENAC staff only, until explicitly promoted |

Each boundary crossing (personal→dept, dept→org, org→foundation, and the ENAC promotion valve) is a **potential leakage path**. Problem 4 is specifically about the **narrowest, highest-consequence** crossing — personal → anything shared — because it is the one crossing SOUL.md names as the nightmare scenario and the one that is genuinely *irreversible* (private personal information, once in a shared/public place, cannot be un-exfiltrated by a later wipe).

### 2.2 STRIDE — the four named leakage paths

| # | Leakage path | S | T | R | I | D | E |
|---|---|---|---|---|---|---|---|
| 1 | **Author publishes from the wrong tier** (intends personal, targets dept/org remote, or vice versa) | — | shared tier gains unwanted content | if one identity can push to multiple tiers, "who put this here" is ambiguous | **primary** — personal info becomes visible to a broader audience than intended | — | the data itself is elevated to a visibility class it was never granted |
| 2 | **A personal file is mis-placed** in a directory that maps to a shared repo (e.g., one Obsidian vault spanning both tiers) | — | the shared tree's contents no longer match its intended scope | — | **primary** | — | same data-privilege-escalation framing as #1 |
| 3 | **Automated sync pushes personal content upward** (a defect or design flaw makes the cadence-sync process itself bidirectional) | — | — | — | **primary, and the worst of the four** — happens silently, with zero human review, on every machine running the agent | — | a background process — one Bob never audits by design — elevates personal data to shared visibility with no human in the loop at all |
| 4 | **A mis-scoped credential** (a key/token with write access to more tiers than intended is used, deliberately or by accident, for the wrong push) | the bearer can act with more tier-identity than they should have | the over-scoped credential can tamper with a tier it shouldn't reach | broad/shared credentials blur "who pushed this," defeating audit | secondary consequence of the tampering | — | **primary — the credential scope IS the enforcement mechanism; if it's wrong, the wall does not exist** |

**DREAD on path #3 (automated sync pushing upward)** — the single highest-severity item in this RFC, because unlike #1/#2/#4 it requires **no human error at all**, only a code defect:

| Factor | Score | Why |
|---|---|---|
| Damage | 10 | Irreversible per SOUL.md — private data in a shared/public place cannot be un-exfiltrated. |
| Reproducibility | 9–10 | If the sync code path *can* push upward, it does so on **every** cadence tick, on **every** machine running the agent — a defect, not a one-off mistake. |
| Exploitability | 9 | Requires no attacker at all — a missing directional guard fires by itself. |
| Affected users | 10 | Every user of every writable tier simultaneously; if the defect reaches the foundation-promotion path, the entire public internet. |
| Discoverability | 9 | Once landed in a dept/org/public repo, trivially found by any teammate, any scanner, anyone browsing history. |

**Average ≈ 9.4/10 — the single highest-severity finding in this document.** It must be closed **by construction** (§2.3), not by review discipline, exactly as SOUL.md already insists.

### 2.3 Structural guarantees (impossible-by-construction, mapped to the paths they close)

| Guarantee | Mechanism | Closes path(s) |
|---|---|---|
| **A — Separate repos/remotes per tier, no shared working tree** | Extend the *same* decision `four-tier-topology.md` §6.2 already made for dept-vs-org confidentiality ("separate repos are the default, everywhere") one tier further down: the personal working tree's `.git/config` has **exactly one** remote (`git@github-personal:…`), physically separate from the dept/org working tree(s), which have their own, different remote(s) and a different credential (`ssh-work`). There is no single directory whose git config contains both a personal and a shared remote. | 1, 2 — "push to the wrong remote" and "file lands in the wrong directory" both require a remote/path to exist that, by construction, does not. |
| **B — Hard tier-selection at the authoring surface** | The Obsidian (or any markdown-editor) workspace the trained author opens is bound to **one** tier's working tree per vault — a "Personal Vault" and a "Department Vault" are two distinct vaults pointed at two distinct directories, never folders inside one vault. The author never faces a "which remote" choice at save/push time; the tool they're in only knows one remote. This is a setup-time (CLI/wizard) concern, not a runtime dropdown that could be misclicked. | 1, 2 |
| **C — Write-direction enforcement: sync only flows DOWN** | The automated cadence-sync/materialize code path (`copilot update`) is **pull-only** against org→dept→foundation and has **no push capability at all** against any shared-tier remote — not "disabled by default," structurally absent from that code path. The *only* way content moves to a broader tier is the existing, separate, human-invoked, explicitly-credentialed action: the author's own `save → push` (ground-truth §3) for personal-tier authors who have no dept/org credential at all, or the one-way `copilot promote` valve (`four-tier-topology.md` §8.2) for private→public. Personal-tier credentials (`ssh-personal`) are never provisioned with write access to any dept/org/foundation remote — so even a defective sync process has no credential with which to push upward. | **3 — the primary fix for the worst path.** Also reinforces 1 and 4 (the credential half). |
| **D — A pre-publish boundary guard (leak-scan) on every writable-tier push** | Generalize the **existing** hard-fail leak scan already specified for the ENAC promotion pipeline (`four-tier-topology.md` §8.2: deny-list for client names, `.env`, tokens, `mcp.json` secrets, internal-knowledge globs) to run on **every** writable-tier push, not only the promotion path — extended with personal-tier markers (a per-user front-matter tag, a personal-only path prefix, PII patterns). A tripped scan **fails the push closed** with a plain-language, non-technical explanation of what to move back to the personal vault — never a raw git/VCS error, per the *Git Error To A Non-Technical Person* anti-pattern. This is **defense-in-depth**, not the primary control — the primary controls are A/B/C (physical separation + no push path); the scan exists for the residual case a determined author manually copy-pastes prose across vaults, which is a content operation no git-topology guarantee can prevent by itself. | 1, 2 (residual human-copy-paste case) |
| **E — No cross-tier credential scope** | Each auth identity is registered against exactly one GitHub account/org and cannot authenticate against the others — `ssh-personal`'s key exists only on the individual's personal GitHub account (no relationship to the enterprise org at all); `ssh-work` exists only against the enterprise org. This is a fact about GitHub account membership, not a policy notice that could be misconfigured — the SSH alias mechanism `four-tier-topology.md` §6.1 already chose for multi-account auth is reused here as the credential half of the leakage wall. **Note the open seam:** this guarantee assumes the two SSH keys/aliases already exist, correctly scoped, on the author's machine — *how they get there* (generation, distribution, rotation) is the open follow-up in §6, not resolved by this guarantee. | 4 |

### 2.4 The one rule that makes personal→shared leakage impossible by construction

This is not a new invention — it is the **concrete mechanism** for the rule SOUL.md §4 already states in prose as the line in the sand for *The Leak*:

> **No working tree, credential, or automated code path that holds personal-tier content is ever configured with write access to a shared-tier (department/org/foundation) remote. Publishing content to a broader tier is always a separate, explicitly-credentialed, human-invoked action performed from that broader tier's own working tree (author push, or the one-way promotion valve) — never a capability of the personal tree or of the background sync scheduler.**

Everything in §2.3 (A–E) is an implementation of this one rule. If this rule holds, paths #1, #2, and #4 require a human to actively defeat physical separation (caught by D as defense-in-depth), and path #3 — the worst one, the one requiring zero human error — becomes **structurally impossible**, because the code that runs unattended, on cadence, without Bob's attention, simply has no remote and no credential with which to push upward, regardless of what defect exists in its logic.

---

## 3. Where each piece lives (invariant #1 discipline)

| Piece | CLI / ecosystem (`copilot`/`cc`/MCP resolver) | MDM-managed domain | Control Tower (the app) |
|---|---|---|---|
| OAuth/device-flow execution + keychain write (Problem 3) | **Owns it** — performs the flow, writes the OS keychain, resolves `requires_secret` at invocation | Optionally forces `AuthMode` for kiosk machines; is the centralized revocation lever | Renders the GUI wrapper around the CLI's device-flow (browser + code), matching the existing sign-in wizard step — holds no secret itself |
| `Signed-out` detection (Problem 3) | Computes it (`doctor --json`) | — | Renders it — the existing badge, no new logic |
| Machine-credential bootstrap for kiosk (Problem 3) | Performs the one-time token exchange | Delivers the bootstrap reference (never the raw secret) via the forced domain | No role |
| Separate per-tier remotes/credentials (Problem 4) | **Owns it** — wizard/`copilot derive` materializes distinct working trees with distinct remotes; `copilot update` structurally lacks push capability upward | No role — this is a repo-topology guarantee, not an MDM concern | No role — Control Tower invokes `copilot update`/`sync now`, never touches git remotes directly |
| Leak-scan / pre-publish guard (Problem 4) | **Owns it** — a CLI-side pre-push/pre-PR check, fail-closed | May supply an org-specific deny-list addendum via the seed generator (Admin mode, §8.1 of `architecture.md`) — still authored through the CLI's guided tool, not hand-edited | Surfaces the plain-language refusal if a push is attempted through any app-visible action; never runs the scan itself |
| `copilot promote` (private→public valve) | **Owns it entirely** — cherry-pick, leak-scan, PR | GitHub Environment approval gate (existing) | No role |
| Trust roots (which OAuth issuer, which minisign key, which update feed) | Compiled-in code | Cannot override security-sensitive keys except from the forced domain, and only within the compiled-in trust set | Renders `IT-config-incomplete` if a required key is absent — never accepts a substitute trust root from anywhere |

Consistent with invariant #1: **if Control Tower vanished, both of these mechanisms would still hold.** Secrets would still live in the keychain via the CLI's own device-flow (headless `copilot auth <integration>` works with no GUI); the leakage wall would still hold because it is a git-topology and credential-scoping fact, not an app-enforced rule.

---

## 4. Invariant impact — RATIFIED

This design **strengthens** invariant #4; it does not weaken or bend it. Specifically:

- It extends "security-sensitive config honored only from the forced/managed domain" to a parallel, previously-unstated rule for **secret material**: secrets are honored only from **per-user OS keychain entries established via interactive auth**, never from any config domain (user, managed, or otherwise) and never from repo content at any tier.
- It extends "trust roots are compiled-in code, not config" to **which OAuth issuers/integrations are trusted at all** — no config domain, forced or not, can add a new trusted secret-acquisition endpoint; that requires a signed CLI release.
- It gives the already-stated *The Leak* line in the sand (SOUL.md §4) a concrete, auditable mechanism rather than leaving it as an aspiration.

**Owner-ratified rules (2026-07-07) — being elevated to `CLAUDE.md` invariants:**

> 1. *"Secrets — API keys, tokens, and integration credentials of any kind — MUST NEVER be committed to, stored in, or transmitted via any tier's git repository, public or private. Inheritance content may reference a secret's name and acquisition method; it may never contain secret material. No git host, including GitHub, is a secrets carrier at any tier."*
>
> 2. *"No working tree, credential, or automated sync code path that holds personal-tier content may ever be configured with write access to a department, org, or foundation remote. Content reaching a broader tier is always an explicit, separately-credentialed, human-invoked action — never a capability of the personal tree or the background sync scheduler."*
>
> 3. *"The automated cadence-sync/materialize path (`copilot update`) possesses pull/read credentials against org→dept→foundation only, in the downward direction, and must not possess push credentials to any shared-tier remote. All upward content movement is performed by a distinct, explicitly invoked command (an author's own push, or `copilot promote`), never by the background scheduler."*
>
> 4. *"Every writable-tier push, and the promotion pipeline, is fail-closed gated by a leak-scan (secrets/tokens, personal-tier markers, PII patterns) before the remote accepts the change. A tripped scan blocks the push and returns a plain-language, non-technical explanation — never a raw git/VCS error surfaced to a non-technical author."*

These four rules are ratified as of 2026-07-07 and are being elevated into `CLAUDE.md`'s invariant set (extending invariant #4's scope). None contradict any existing invariant, red-team finding, or SOUL.md anti-pattern; #2–#4 are the concrete mechanism for prose that already exists (SOUL.md's *The Leak* line in the sand, `four-tier-topology.md` §8.2's leak-scan and one-way promotion valve).

---

## 5. Residual unknowns / open questions

1. **MCP secret-injection transport** — env-var injection at process spawn vs. a short-lived local socket handoff is not yet specified as a CLI-contract schema addition; needs its own WS-A-style spec before implementation.
2. **Leak-scan deny-list authorship and coverage** — who authors the personal-tier marker patterns (ENAC default vs. org-specific addendum via Admin mode), and the scan's honest limit: it is a **backstop**, not a guarantee — it cannot catch a determined author manually retyping personal prose with no recognizable pattern. The real guarantee is structural separation (§2.3 A–C); this must be documented as such wherever the scan is described, so it is never mistaken for the primary control.
3. **Kiosk/shared-machine credential depth** — this RFC's §1.5 exception depends on the still-open kiosk/multi-user decision (`architecture.md` §11 item 3, red-team B-H7); the machine-credential bootstrap sketched here should be revisited once that decision lands.
4. **No-IdP, no-OAuth micro-company edge case** — a 3-person team with literally no identity provider and integrations that support neither OAuth nor a keychain-friendly device flow degrades to manual one-time keychain paste; not fully stress-tested for how many real target integrations actually lack OAuth support.
5. **Interaction with the (separately unresolved) merge-conflict/multi-writer problem** — if a future invisible-merge-conflict resolver ever needs to reach across a personal↔shared boundary to resolve a collision (e.g., pulling in a personal draft to auto-merge a dept file), it must remain tier-scoped and never cross the wall this RFC establishes. Flagged for whoever designs that resolver; not designed here.
6. **Revocation SLA for legacy static-key integrations** — an integration with no OAuth/device-flow (key-only) has no fast, centralized revocation path beyond asking the vendor to rotate the key; this is a real residual gap the no-cloud-secret-store fallback does not fully close.

---

## 6. Open follow-up carried forward from ratification — author git-push-credential provisioning (NOT YET DESIGNED)

**This is the one piece of this document that is a principle, not a mechanism, and it must not be mistaken for a closed item.**

Section 2.3's guarantees (A, C, E) all depend on `ssh-personal` and `ssh-work` existing as distinct, correctly-scoped SSH keys/aliases on the author's machine *before* any of the structural guarantees can hold. This RFC reuses the four-tier SSH-alias **model** (`four-tier-topology.md` §6.1) as the credential-scoping mechanism, but that source document specifies the *selector shape* (host aliases mapped to identities), not:

- how `ssh-personal` and `ssh-work` keys are **generated** (locally, at wizard time? centrally, by IT, then delivered?),
- how they are **distributed** to a new machine without ever transiting a channel this document would itself classify as a secrets carrier (i.e., the private key itself is exactly the kind of secret material §1 forbids from git — so the provisioning path cannot reuse the inheritance-content mechanism at all),
- how a **compromised or rotated** key is revoked and re-issued across every machine an author uses, and
- how this reconciles with the **existing, separately-specified integration-secret keychain mechanism** (§1.4) — is the git SSH key itself keychain-resident too, or does it use `ssh-agent`/`.ssh/` convention, and if the latter, does that constitute an exception to "never touches disk as a plaintext file" that needs its own justification?

**Disposition:** flagged as an **explicit open follow-up requiring a fully worked design before implementation** — not resolved by this document, and not to be treated as solved by reference to `four-tier-topology.md` §6.1 alone. Whoever picks this up should produce a WS-A-style spec (mirroring residual unknown §5.1's treatment) before any code implements author-side git push credentials.
