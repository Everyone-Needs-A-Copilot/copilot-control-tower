# Credentials Carrier & the Personal↔Shared Leakage Wall

| | |
|---|---|
| **STATUS** | **RATIFIED 2026-07-07 (owner).** Promoted from `docs/01-architecture/proposals/credentials-and-boundary.md` (DRAFT PROPOSAL). This is now the canonical security design for the two open foundational problems logged in [`SOUL.md`](../../SOUL.md) §9 ("credentials-carrier problem," "writable-tier vs never-destroy tension" as it bears on leakage) and `interview-ground-truth.md` §10. **Amended 2026-07-07 (owner-requested: shared secret store; author push-credential mechanism).** The amendment is additive — it introduces one new, optional, higher-precedence rung on the existing credential-resolution ladder (§1.6) and closes the one previously-open seam (§6, author push-credential provisioning, now RESOLVED). Nothing previously ratified is weakened or reopened. **Conformed 2026-07-08 to `cse-alignment-decisions.md`:** MDM is dropped completely (D4); the shared secret-store endpoint (§1.6.2, §1.6.3) is rehomed from the MDM forced domain to inherited org repo config, and offboarding (§1.4) is recast as GitHub-access revocation plus shared-secret-store token rotation. Personal-key multi-machine sync is added as an accepted, open-design goal (§7, D7.3). |
| **Author** | Security engineering pass (STRIDE + DREAD) |
| **Scope** | Problem 3 (credentials carrier) and Problem 4 (personal↔shared leakage wall), **plus the 2026-07-07 amendment**: Enhancement A (shared secret store, §1.6) and Enhancement B (author push-credential provisioning, §6 — resolves the previously carried-forward seam). Does **not** resolve the third open problem (writable-tier vs never-destroy tension) or the merge-conflict UX — those remain separate, unresolved (see `inheritance-and-publish.md`). |
| **Reads on** | `CLAUDE.md` invariants (esp. #4), `architecture.md` §6–§9, `cli-contract.md`, `four-tier-topology.md` §6, §8–9, this doc's sibling `security-and-trust.md` (stub — updated to point here). |
| **Governing rule for this whole document** | Invariant #1 (parse, never compute) applies to security architecture exactly as it applies to health status: **Control Tower renders and invokes; it never holds a secret, a credential decision, or a trust root.** Every mechanism below is placed in the CLI/ecosystem layer, signed inherited org/foundation config, or (rarely) a third-party authoring tool — never in the app. |
| **Carried-forward seam — RESOLVED 2026-07-07** | The **author git-push-credential provisioning** mechanism (how `ssh-personal`/`ssh-work` SSH keys are actually generated, distributed to, and rotated on an author's machine) was specified only **in principle** at ratification. It is now fully worked in §6 — per-user, on-device SSH keypair + GitHub's own team-membership ACL, reusing existing primitives from `four-tier-topology.md` §6.1/§6.3 and the §1.4 OAuth-device-flow mechanism. No code should have implemented author-side git push credentials before this section existed; it now exists. |

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
| **C — an OS-level managed configuration profile carrying the secret value itself** | A managed-preferences/profile payload contains the raw API key. | **Rejected.** Push-once, hard to rotate centrally, itself a file that can be exported/inspected on the endpoint, and, most importantly, it would mean a security-sensitive *secret* travels through the *same* channel invariant #4 reserves for **config values**, not secret material. Conflating "trusted channel" with "safe to carry raw secrets" is the anti-pattern. Moot in this product regardless: Control Tower carries no MDM/managed-profile surface at all (`cse-alignment-decisions.md` D4); where a *non-secret* value (the shared secret-store endpoint) needs a trusted delivery channel, it is delivered via inherited org repo config instead (§1.6.2). |
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

**No MDM in this product (D4):** the per-user keychain + interactive OAuth/device-flow mechanism above is the *only* mechanism; it applies identically to every machine, with no managed/forced-config variant and no fleet-machine special case. Offboarding revokes the person's GitHub access and rotates any shared-secret-store tokens (§1.6.5); that is the actual revocation lever, not a device-management flag. **Accepted residual:** content already synced to a departed person's disk is not remotely wiped (there is no MDM to reach the device), which is an acceptable trade-off for the product's target of small, trusted orgs (`cse-alignment-decisions.md` D4).

Trust roots for *which* OAuth issuer/endpoint is trusted per integration remain **compiled-in code, not config** (invariant #4): no user-editable or inherited config value can repoint an integration's OAuth endpoint; only a signed CLI release can add or change a trusted integration.

### 1.5 Kiosk/lab machine credential, dropped (D4)

The prior design proposed a narrow MDM-triggered bootstrap exchange for unattended kiosk/lab machines (a machine credential provisioned via a managed profile). **Dropped** along with the rest of the MDM surface (`cse-alignment-decisions.md` D4: no MDM, no forced/managed configuration domain, no fleet dashboard). Kiosk/shared-machine credential provisioning is out of scope for this product. If a future need for unattended shared-machine credentials arises, it must be designed against a non-MDM mechanism (e.g. the same per-user OAuth device-flow, run by whoever is physically present) rather than reintroducing a managed-profile bootstrap.

### 1.6 Enhancement A — Shared secret store (recommended, owner-requested 2026-07-07)

**The request:** the current mechanism (§1.4) is purely per-user. A department/org that already runs, or is willing to stand up, a **self-hosted, IT-managed secret store** wants members of that tier to share integration credentials, so onboarding a department with many integrations doesn't mean re-authenticating every person against every integration. The owner already runs a cloud secret store on a **Coolify** server and believes any IT org could stand one up securely. This is designed below as an **additive, optional, higher-precedence rung** on the existing ladder (§1.6.3) — it changes nothing about §1.4's mechanism, which remains the unconditional floor (§1.6.6).

#### 1.6.1 Tool research and recommendation

Evaluated 2026-07-07 against: OSS license (self-hostable with no commercial gate), realistic Coolify-deployability, access-control granularity, TLS, secret versioning, rotation tooling, audit log, and a machine-readable API (for `copilot`'s non-interactive resolution).

| Store | License | Coolify-deployable | Access control | Versioning / rotation | Audit log | Verdict |
|---|---|---|---|---|---|---|
| **Infisical** | MIT (fully OSS) | **Official Coolify service template** — one-click | Project → environment RBAC; **machine identities** (Universal Auth / OIDC / cloud-native auth) issue short-lived access tokens scoped per environment — the right shape for a tier-scoped read | Native point-in-time secret versioning; native scheduled rotation (Postgres/MySQL/Mongo, AWS IAM, custom webhook rotation) | Built-in, queryable by user/secret/environment/time, streamable to a SIEM | **Primary recommendation** |
| **OpenBao** (Linux Foundation fork of Vault, MPL 2.0) | MPL 2.0 — true OSS, no BSL competitive-use restriction (unlike Vault OSS's BSL 1.1) | No official one-click Coolify template, but deploys cleanly via Coolify's generic Docker-Compose import — it is the same single-binary/Docker-image shape as upstream Vault | Full policy-as-code ACL (paths/capabilities); namespaces (multi-tenancy) free — Enterprise-only on Vault OSS | KV v2 versioning; mature dynamic-secrets engines (DB, PKI, SSH) with leases | Full audit device (file/syslog/socket) | **Alternative** — pick when the org already runs Vault-family tooling/Terraform, or wants free namespace multi-tenancy |
| Doppler | Proprietary; on-prem edition only announced June 2026, Enterprise-tier licensed appliance | Not a self-hostable OSS artifact — no community Coolify template; on-prem is a paid license, not a Docker image an IT admin freely deploys | — | — | — | **Rejected** — fails the "self-hostable OSS" bar this enhancement requires |
| Vaultwarden (unofficial Bitwarden server) | GPLv3, self-hostable, official Coolify service | Deploys on Coolify easily | — | Bitwarden never released **Secrets Manager** (the machine-read/audit/rotation product) under GPLv3 — Vaultwarden has no native machine API, secret versioning, or audit trail for this use; only an unofficial bridge (`Vaultwarden-API`) approximates one | — | **Rejected for this use** — a good self-hosted password vault for humans, not built for the machine-read/audit/rotation contract this enhancement needs |

**Primary: Infisical.** **Alternative: OpenBao.** Both are genuinely self-hostable OSS and both deploy on the owner's own Coolify posture — Infisical via Coolify's official template (`coolify.io/docs/services/infisical`), OpenBao via Coolify's generic Docker-Compose deploy path.

#### 1.6.2 IT setup path (recommended, concise)

1. **Deploy** the chosen store on IT-managed infrastructure via Coolify's one-click template (Infisical) or Docker-Compose import (OpenBao) — the same posture the owner already runs.
2. **Enforce TLS** at the Coolify proxy (Traefik/Caddy + Let's Encrypt); the store's API is never exposed over plaintext, including on an internal network.
3. **Scope access by tier membership, not by a parallel individual grant list.** Map the store's RBAC unit (an Infisical project/environment, or an OpenBao namespace/policy) 1:1 to a tier — one per department, one for org. Grant access using the **same GitHub-team-membership fact** `four-tier-topology.md` §6.3 already established for repo ACLs; where the store supports SSO/OIDC (both do), point it at the same IdP already gating GitHub SSO, so tier membership has one source of truth, not two to keep in sync.
4. **Enable rotation** natively (Infisical scheduled rotation; OpenBao dynamic secrets/leases) on a per-secret cadence appropriate to the integration — never disabled "for convenience."
5. **Enable the audit log**, shipped to wherever IT already centralizes logs — this is the repudiation half of STRIDE for shared credentials (§1.6.5).
6. **Deliver the store's URL/config via inherited org repo config only** (invariant #4, rehomed per `cse-alignment-decisions.md` D4): a signed value in the org tier's inherited config (e.g. `shared_secret_store_url`, `shared_secret_store_tier`), never a value committed as a secret and never a user-editable local config file. The endpoint URL itself is not a secret; access to the store remains gated by the reader's own GitHub-team membership/token, so a machine that inherits a store URL it isn't authorized against simply gets a 403 from the store, not a leak. If no org config key is present, the CLI treats the shared-store rung as **absent**, never misconfigured, and falls through the ladder (§1.6.3) without guessing a URL from convention or environment.

#### 1.6.3 Tier mapping and the full credential-resolution ladder

Extends §1.4's fallback chain with one new, higher-precedence rung. **The full ladder, in order, fail-closed at every rung:**

1. **Managed shared secret store**: if `shared_secret_store_url` is present in the inherited org tier config **and** the CLI's machine identity/service-token resolves the member as authorized for that tier's project/namespace (by their own GitHub-team membership), the CLI performs a scoped, authenticated API read (never a static bearer baked into a config file) and caches nothing to disk beyond the invoking process's lifetime.
2. **Per-user OS keychain cache** (§1.4) — used when the store is absent, unreachable, or the member isn't authorized for that tier's store.
3. **Interactive OAuth/device-code flow** (§1.4) — used when no keychain entry exists yet; result is written to keychain for next time.
4. **One-time secure paste** (§1.4's manual floor) — for legacy key-only integrations with no OAuth support.

A miss at any rung falls through to the next; a miss at **all four** surfaces the existing `Signed-out` finding (§1.4) — never a silent no-op, never a stale value used past its TTL. **Tier resolution for rung 1 follows the same nearest-wins precedence as inheritance content itself:** a personal-tier `requires_secret` reference never checks a shared store (personal has no tier-scoped store by definition); a department-tier reference checks the department store, then the org store, never the reverse.

#### 1.6.4 Invariant intact — the store is not the inheritance channel

The shared store changes **where** an authorized member resolves a `requires_secret: <NAME>` reference at runtime; it changes **nothing** about what inheritance content carries. Skill/MCP manifests still declare only the name and acquisition method (§1.4) — never a value, never a connection string, never store credentials. The store is a **resolution-time API the CLI calls**, not a channel content flows through — git remains, unconditionally, not a secrets carrier at any tier, exactly as ratified rule 1 (§4) states.

#### 1.6.5 Security analysis — shared vs. per-user (the trade-off, stated honestly)

Shared credentials genuinely reduce per-user attribution and enlarge blast radius; this must not be minimized:

| Factor | Per-user credential | Shared credential |
|---|---|---|
| Attribution / audit | Every use traces to one person's own OAuth grant | The store's audit log traces which authorized *member's service-token* fetched the secret, not which action that person then took with it downstream — a real, residual repudiation gap |
| Blast radius on compromise | One person's access | Every current tier member's access to that one integration, simultaneously |
| Onboarding cost | Re-authenticate per person, per integration | One-time IT setup, then automatic for every tier member |

**Recommended policy — flagged for owner confirmation, this is a judgment call, not a mechanical derivation:**

- **Appropriate to share:** credentials for a **shared-service integration used identically by every member of a tier**, where the integration has no per-user identity concept — a department's shared DB read-replica credential, a shared CRM API key used by an automation, a shared LLM-provider key billed to the department, a shared Slack **app** bot token (not a personal OAuth grant).
- **Must stay per-user:** any credential that **acts as an individual's identity** (a personal OAuth grant that posts *as* that person), anything where **least-privilege or per-action attribution matters** (financial transactions, PII, or anything an audit must later attribute to a named person), and anything a vendor's own ToS scopes to a named individual (most per-seat SaaS OAuth grants). **Author git-push credentials are never shared-store material, regardless of tier** — see §6.4.

**Rotation, revocation, leaver flow:**
- Rotation uses the store's native mechanism (§1.6.2 step 4); the CLI's rung-1 read is process-lifetime-only (never disk-cached), so a rotated value takes effect on the next invocation, not on next full re-auth.
- **Revocation ties to deprovision** (`architecture.md` §8.3, "the real backstop is server-side token revocation"): removing a person from the tier's GitHub team — the same membership fact gating store access (§1.6.2 step 3) — simultaneously revokes their store authorization. One action, not two systems to remember.
- **When a member leaves the tier:** access is revoked by that same team-membership removal. The shared secret **value itself** is rotated only if the leaver's access pattern created genuine exposure risk (they could exfiltrate the raw value, not merely call an API through it) — an IT judgment call, defaulting to rotate-on-leave for anything in the "must stay per-user" class that was mistakenly shared, and an audit-log review for the "appropriate to share" class.

#### 1.6.6 The graceful floor — no shared store configured

Stated explicitly, per the owner's original worry: a company with **no** shared secret store configured is not blocked. The existing §1.4 mechanism — per-integration OAuth/device-code, keychain-resident, one-time secure paste as the manual floor — **is** the floor, unconditionally, and requires nothing purchased or deployed. Enhancement A is additive precedence, never a requirement; the ladder in §1.6.3 degrades gracefully to exactly the RATIFIED §1.4 mechanism whenever rung 1 is absent.

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
| **E — No cross-tier credential scope** | Each auth identity is registered against exactly one GitHub account/org and cannot authenticate against the others — `ssh-personal`'s key exists only on the individual's personal GitHub account (no relationship to the enterprise org at all); `ssh-work` exists only against the enterprise org. This is a fact about GitHub account membership, not a policy notice that could be misconfigured — the SSH alias mechanism `four-tier-topology.md` §6.1 already chose for multi-account auth is reused here as the credential half of the leakage wall. **Provisioning resolved 2026-07-07:** this guarantee assumes the two SSH keys/aliases already exist, correctly scoped, on the author's machine — *how they get there* (generation, distribution, rotation) is now fully worked in §6 (per-user on-device key + GitHub team-membership ACL). | 4 |

### 2.4 The one rule that makes personal→shared leakage impossible by construction

This is not a new invention — it is the **concrete mechanism** for the rule SOUL.md §4 already states in prose as the line in the sand for *The Leak*:

> **No working tree, credential, or automated code path that holds personal-tier content is ever configured with write access to a shared-tier (department/org/foundation) remote. Publishing content to a broader tier is always a separate, explicitly-credentialed, human-invoked action performed from that broader tier's own working tree (author push, or the one-way promotion valve) — never a capability of the personal tree or of the background sync scheduler.**

Everything in §2.3 (A–E) is an implementation of this one rule. If this rule holds, paths #1, #2, and #4 require a human to actively defeat physical separation (caught by D as defense-in-depth), and path #3 — the worst one, the one requiring zero human error — becomes **structurally impossible**, because the code that runs unattended, on cadence, without Bob's attention, simply has no remote and no credential with which to push upward, regardless of what defect exists in its logic.

---

## 3. Where each piece lives (invariant #1 discipline)

| Piece | CLI / ecosystem (`copilot`/`cc`/MCP resolver) | Signed inherited org/foundation config | Control Tower (the app) |
|---|---|---|---|
| OAuth/device-flow execution + keychain write (Problem 3) | **Owns it** — performs the flow, writes the OS keychain, resolves `requires_secret` at invocation | No role: revocation is via GitHub-access removal plus shared-secret-store token rotation (D4), not a config domain | Renders the GUI wrapper around the CLI's device-flow (browser + code), matching the existing sign-in wizard step — holds no secret itself |
| `Signed-out` detection (Problem 3) | Computes it (`doctor --json`) | — | Renders it — the existing badge, no new logic |
| Separate per-tier remotes/credentials (Problem 4) | **Owns it** — wizard/`copilot derive` materializes distinct working trees with distinct remotes; `copilot update` structurally lacks push capability upward | No role — this is a repo-topology guarantee, not a config-domain concern | No role — Control Tower invokes `copilot update`/`sync now`, never touches git remotes directly |
| Leak-scan / pre-publish guard (Problem 4) | **Owns it** — a CLI-side pre-push/pre-PR check, fail-closed | May supply an org-specific deny-list addendum via the seed generator (Admin mode, §8.1 of `architecture.md`) — still authored through the CLI's guided tool, not hand-edited | Surfaces the plain-language refusal if a push is attempted through any app-visible action; never runs the scan itself |
| `copilot promote` (private→public valve) | **Owns it entirely** — cherry-pick, leak-scan, PR | GitHub Environment approval gate (existing) | No role |
| Trust roots (which OAuth issuer, which minisign key, which update feed) | Compiled-in code | Cannot override security-sensitive keys except from this signed, inherited config, and only within the compiled-in trust set | Renders `IT-config-incomplete` if a required key is absent — never accepts a substitute trust root from anywhere |
| Shared secret store connection (Enhancement A, §1.6) | **Owns it** — performs the scoped, authenticated API read at `requires_secret` resolution time; caches nothing beyond process lifetime | **Owns delivery of the store URL/config** (the only channel by which a store endpoint may reach a machine, rehomed from MDM to inherited org repo config per D4); absent key ⇒ CLI treats rung as absent, never guesses | No role — renders `Signed-out`/store-unreachable exactly like any other resolution miss, holds no store credential itself |
| Author git-push credential generation, registration, rotation, revocation (Enhancement B, §6) | **Owns it entirely** — generates the on-device keypair, registers/rotates the public key via GitHub's API (itself authenticated via the §1.4 OAuth device-flow), never handles the private key beyond the local keychain-backed `ssh-agent` write | No role — authorization is GitHub Team membership, a fact about the enterprise's own GitHub org, not a config-domain value | No role — Control Tower never touches the private key or the registration call |

Consistent with invariant #1: **if Control Tower vanished, both of these mechanisms would still hold.** Secrets would still live in the keychain via the CLI's own device-flow (headless `copilot auth <integration>` works with no GUI); the leakage wall would still hold because it is a git-topology and credential-scoping fact, not an app-enforced rule.

---

## 4. Invariant impact — RATIFIED

This design **strengthens** invariant #4; it does not weaken or bend it. Specifically:

- It extends "security-sensitive config honored only from signed, inherited org/foundation config" to a parallel, previously-unstated rule for **secret material**: secrets are honored only from **per-user OS keychain entries established via interactive auth**, never from any config domain (user, inherited, or otherwise) and never from repo content at any tier.
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

### 4.1 Proposed wording broadening, RESOLVED by `cse-alignment-decisions.md` D4 (2026-07-08)

Enhancement A (§1.6) introduces a second carrier, but only for the store's **endpoint reference**, not for a secret value, alongside the per-user OS keychain that §1.4/§1.2's bullet 1 and the invariant text above name as the sole honored carrier for secret *values*. The current wording (this section, and the equivalent invariant elevated to `CLAUDE.md`) says secrets are honored **only from per-user OS keychain entries**; this remains true for secret *values*, and what changes is where the store's endpoint is sourced from. Per D4, MDM is dropped completely, so the endpoint is delivered via **inherited org repo config**, not a managed/forced device domain:

> **Current:** *"secrets are honored only from per-user OS keychain entries established via interactive auth, never from any config domain (user, managed, or otherwise) and never from repo content at any tier."*
>
> **Adopted:** *"secrets are honored only from a per-user OS keychain entry established via interactive auth, **or from a tier-scoped managed secret store whose connection endpoint is delivered via inherited org repo config (the endpoint URL is not a secret; access to the store remains gated by the reader's own GitHub-team membership/token)**, never from any user-editable local config domain and never from repo content at any tier."*

This broadening is now **adopted**, not merely proposed: `cse-alignment-decisions.md` D4 resolves it by dropping MDM as a carrier and rehoming endpoint delivery to inherited org repo config. Nothing about secret *values* changes; they remain keychain-only or store-resolved at runtime, never in git.

---

## 5. Residual unknowns / open questions

1. **MCP secret-injection transport** — env-var injection at process spawn vs. a short-lived local socket handoff is not yet specified as a CLI-contract schema addition; needs its own WS-A-style spec before implementation.
2. **Leak-scan deny-list authorship and coverage** — who authors the personal-tier marker patterns (ENAC default vs. org-specific addendum via Admin mode), and the scan's honest limit: it is a **backstop**, not a guarantee — it cannot catch a determined author manually retyping personal prose with no recognizable pattern. The real guarantee is structural separation (§2.3 A–C); this must be documented as such wherever the scan is described, so it is never mistaken for the primary control.
3. **Kiosk/shared-machine credential depth**: §1.5's MDM-based kiosk bootstrap is dropped (D4, `cse-alignment-decisions.md`); if unattended shared-machine credentials are needed later, a non-MDM mechanism must be designed from scratch (`architecture.md` §11 item 3, red-team B-H7 remain open, now without an MDM-based answer).
4. **No-IdP, no-OAuth micro-company edge case** — a 3-person team with literally no identity provider and integrations that support neither OAuth nor a keychain-friendly device flow degrades to manual one-time keychain paste; not fully stress-tested for how many real target integrations actually lack OAuth support.
5. **Interaction with the (separately unresolved) merge-conflict/multi-writer problem** — if a future invisible-merge-conflict resolver ever needs to reach across a personal↔shared boundary to resolve a collision (e.g., pulling in a personal draft to auto-merge a dept file), it must remain tier-scoped and never cross the wall this RFC establishes. Flagged for whoever designs that resolver; not designed here.
6. **Revocation SLA for legacy static-key integrations** — an integration with no OAuth/device-flow (key-only) has no fast, centralized revocation path beyond asking the vendor to rotate the key; this is a real residual gap the no-cloud-secret-store fallback does not fully close.
7. **Shared-store outage UX (Enhancement A, §1.6)** — the ladder (§1.6.3) specifies fail-through-to-keychain on an unreachable store, but the non-technical-facing wording for "the department store is unreachable, falling back to your own sign-in" has not been drafted or tested with a Bob-class user; needs its own pass before Enhancement A ships broadly.
8. **Shared-vs-per-user classification list (§1.6.5)** — the *policy* (which integration classes are shareable) is recommended here but not yet ratified per-integration; a concrete allow/deny list per common integration (Slack, Notion, LLM providers, CRMs, DBs) should be authored and owner-confirmed before IT orgs start classifying their own integrations.
9. **Shared secret store never validated with a real multi-department rollout** — like the broader authoring loop (§9 of `interview-ground-truth.md`), Enhancement A is a **design, not yet dogfooded**; recommend prototyping with the owner's own Coolify-hosted store before generalizing the IT setup path (§1.6.2) as prescriptive guidance for external IT orgs.
10. **Personal-key multi-machine sync carrier/mechanism**: accepted as a goal (§7, D7.3), but the exact carrier is not chosen; must reconcile with the per-machine locality §1.4/§6.1 currently rely on as a security property, not merely a limitation.

---

## 6. Author git-push-credential provisioning — RESOLVED 2026-07-07 (Enhancement B)

**Status change:** at ratification this section was a placeholder — "a principle, not a mechanism." Per owner request the same amendment date, it is now a **fully worked mechanism**. Nothing in §2.3's structural guarantees (A, C, E) changes as a result of resolving this — those guarantees already assumed `ssh-personal`/`ssh-work` exist, correctly scoped, on the author's machine; this section specifies **how they get there.**

### 6.1 Recommended mechanism: per-user, on-device SSH key + GitHub's own team-membership ACL

**Generation.** At the moment an author is promoted (`inheritance-and-publish.md` §2.4 — "a provisioning event: add a writable authoring checkout + a write credential"), the CLI generates an ed25519 keypair **on the author's own machine**. The **private key never leaves the machine**: it is written to the OS keychain-backed `ssh-agent` (macOS: a Keychain item unlocked by the user's login session, e.g. `ssh-add --apple-use-keychain`; the Windows Phase-4 re-skin uses the platform `ssh-agent` service + Credential Manager), never to a bare plaintext file a git working tree or backup tool could pick up as content, and never logged.

**Registration.** The **public** key — not secret material; this is the entire point of asymmetric auth, and is why registering it does not reopen the "secrets never travel as content" rule in §1 — is registered as a personal SSH key on the author's **own** GitHub account (the same account already SSO'd into the enterprise org for the `ssh-work` alias, `four-tier-topology.md` §6.1). This is a deliberate choice over a shared deploy key or a machine-user account, for one reason: **GitHub's real access-control primitive for "which repos can this identity push to" is org Team membership on a personal account** (`four-tier-topology.md` §6.3 — "map access with GitHub's real primitives"), not the SSH key itself. The key only proves *who*; GitHub's server-side ACL decides *where*. Reusing this existing primitive means least privilege is enforced by GitHub, server-side — not by a Control-Tower-side scoping rule that could be misconfigured or bypassed.

**Authorization (least privilege).** The promotion event grants the author's GitHub identity membership in **exactly** the team(s) owning the tier repo(s) they are trained/authorized for (e.g., `acme-corp/engineering` → write on `copilot-dept-engineering` only). No broader grant is made. An author trained for one department has no path to push to another department's repo, or to org: GitHub returns a 403 at the transport layer, because the restriction lives in team membership — authoritative and server-side — not in anything the key or the CLI encodes.

**A non-author cannot obtain a shared-tier push credential**, by construction: there is no shared credential object to leak, copy, or hand out. Every author's push credential is that individual's own personal SSH key, authenticated as their own GitHub identity, gated by their own team membership. Compromising one author's key yields exactly that author's existing scope — never more, and never a scope other authors also hold.

### 6.2 Rotation

Author-initiated (`copilot auth rotate-key --tier work`, or a periodic CLI-surfaced reminder): the CLI regenerates the keypair on-device and replaces the registered public key via the GitHub API. That API call is itself authenticated via the **same per-user OAuth device-flow already specified in §1.4** for integration secrets — GitHub becomes one more integration the CLI can drive a device flow for (scope: manage the author's own SSH keys), so no raw personal-access-token is ever pasted. This reuses existing machinery rather than inventing a second secret-acquisition path.

### 6.3 Revocation on deprovision

Two independent, composable levers, both reusing already-ratified patterns:

1. **Team-membership removal** — the fast, centralized lever (`architecture.md` §8.3, "the real backstop is server-side token revocation"). Removing the author from the tier's GitHub Team instantly removes their push capability, regardless of the local key's state. This is what IT/deprovision should reach for by default.
2. **Key-level removal** — for a suspected-compromise case (not routine deprovision), IT or the author additionally deletes the specific public key from the author's GitHub account via the API, invalidating that one key without touching team membership (useful when the same person keeps authoring from a different, trusted machine).

Both are ordinary GitHub API calls against existing primitives — no new revocation engine, consistent with how integration-secret revocation already works in §1.4.

### 6.4 Where the shared secret store (Enhancement A) does — and does not — help

**Does not help** for the primary path: an author's own git push credential is, by design, personal and non-shared (§6.1) — placing it in the shared store would recreate exactly the shared-credential attribution/blast-radius trade-off §1.6.5 says must *not* apply to this class of credential. The shared store is the wrong home for a per-person identity credential, full stop.

**Does help**, narrowly, for a genuinely different object: `four-tier-topology.md` §6.1's `gh-app:<slug>` path for **CI/shared runners with no per-developer identity** already requires a long-lived **GitHub App private key** held centrally and exchanged for short-lived installation tokens at clone time. That private key *is* exactly the kind of secret material the shared store (§1.6) is built for — IT should hold the GitHub App private key in the department/org store (rotated, audited, versioned) rather than on any individual's machine or in a CI runner's plaintext config. This is additive and does not change anything in §6.1–§6.3.

### 6.5 Reconciling with the integration-secret keychain mechanism (§1.4)

Answering the four questions this section originally left open, resolved same-day as ratification:

- **Generated on-device**, at promotion time — never centrally, never delivered pre-made.
- **Distributed** without ever transiting a secrets-carrier channel: only the **public** half is registered anywhere; public keys are not secret material.
- **Rotation/revocation** — §6.2/§6.3, both GitHub-API-native, no bespoke machinery.
- **Relationship to §1.4's keychain mechanism** — this is an intentional, justified variant, not an exception: the private key lives in the OS keychain-backed `ssh-agent`, the platform-native storage for SSH identities (Keychain access-control-gated — the same security property `Security.framework` provides for integration tokens), never a bare `~/.ssh/id_ed25519` plaintext file. This does not weaken "never touches disk as plaintext" — the keychain-backed agent is the SSH-specific instance of the same OS secure-storage guarantee §1.4 already relies on.

**Disposition: RESOLVED.** The carried-forward seam from ratification (top-of-doc table; `inheritance-and-publish.md` §7) is closed by this mechanism. Guarantee E in §2.3 is now fully satisfied, not merely assumed.

---

## 7. Personal-key multi-machine sync, accepted goal, open design item (D7.3)

**Status:** accepted per `cse-alignment-decisions.md` D7.3, answering CSE open question 4 (`copilot-solutioning-ecosystem.md`, "Open design questions" item 4). This section states the goal and the constraint it must reconcile with. It is **not** a mechanism design, and should not be read as one.

**The goal.** A user who works from more than one of their own machines (e.g. a laptop and a desktop) currently re-establishes each personal credential independently, per machine: the per-user OS keychain entry (§1.4) and the per-machine on-device SSH keypair (§6.1) are both, by design, local to the machine they were created on. The accepted goal is to let a user sync their **own** personal keys across their **own** machines, ending the `.env`/credential hand-copying this currently forces.

**What this is not.** This is not the shared secret store (§1.6): that store is tier-scoped, accessed by GitHub-team membership, and explicitly excludes anything that acts as an individual's identity (§1.6.5, "must stay per-user"). Personal-key sync is the opposite case: one person, several machines only they control, syncing credentials that remain theirs alone and are never shared with anyone else on their tier.

**The constraint it must reconcile with.** §1.4 and §6.1 both currently treat **per-machine** provisioning as a security property, not merely a limitation:

- The OS keychain entry is deliberately per-user *and* per-machine, so a credential compromised on one machine does not, today, imply the others are exposed.
- The on-device SSH keypair (§6.1) is deliberately generated **on** the author's machine, with the private key never leaving it, specifically so a compromised key has a single, revocable, machine-scoped blast radius.

A sync mechanism that moves these values between machines must preserve "never travels through git or any shared-tier carrier" (§1, §2.4) while giving up strict single-machine locality. That is a genuine design tension, not a checkbox.

**Open, not specified here.** The exact carrier/mechanism is undecided. Candidates worth evaluating later (not a decision, not a shortlist ranking) include the OS's own cross-device keychain sync where the platform provides one (scoped to devices signed into the same personal account), a personal end-to-end-encrypted sync mechanism, or a personal-scale analogue of the shared-store pattern (§1.6) bound to exactly one person's own device set rather than a GitHub team. Whichever is chosen must still satisfy: never git, never a shared-tier carrier, revocable per-device, and reconciled with the per-user on-device SSH key model (§6). It is specifically **not yet decided** whether the git-push private key itself is ever synced, versus each machine simply keeping its own keypair registered separately under the same GitHub identity (which would sidestep the sync question for that one credential class entirely).

This is flagged as an **open design item**, not resolved by this document.
