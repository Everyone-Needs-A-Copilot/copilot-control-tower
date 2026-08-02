# Self-service store provisioning — GitHub-verified, admin-free

| | |
|---|---|
| **STATUS** | **DESIGN FOR REVIEW.** Not ratified, not a plan, no code. A security threat-model pass runs next on this document and will extend §7. Everything this document proposes that does not exist today is marked **[NEW]**; every capability claim about Infisical or GitHub carries a verification status in §3. |
| **Decision it serves** | The owner's ratified direction (2026-08-02): *"I'm already connected to the company's repository through GitHub — use that as the authentication method to connect to my Infisical setup and automatically create that username, Client ID, and Client Secret."* This resolves the G-6 fork in [`.copilot/wp/395.md`](../../.copilot/wp/395.md) §c in favour of GitHub-verified self-service. What remains open, and what this document answers, is **which of three mechanisms** delivers it. |
| **Relationship to the ratified architecture** | This is intended as the concrete realization of [`credentials-and-boundary.md`](credentials-and-boundary.md) §1.6 — specifically §1.6.2 step 3 ("scope access by tier membership, not by a parallel individual grant list") and §1.6.5 ("removing a person from the tier's GitHub team … simultaneously revokes their store authorization"). **Two deviations from that text are named explicitly in §6.4** and must be ratified or rejected rather than absorbed silently. |
| **Evidence base** | `.copilot/wp/395.md` (the forensic trace: D-1..D-9, G-1..G-12, RD-1) · `credentials-and-boundary.md` §1.4–§1.6, §6.1–§6.5 · [`connect-experience-walkthrough.md`](../03-design/connect-experience-walkthrough.md) and `walkthroughs/15-connect-experience-uxd-walkthrough.html` (the Bob experience this must make real) · live `~/.claude/ecosystem.yml` (the real `store:` block, the empty `team_scopes:`, `github_app.client_id`) · `claude-copilot/tools/cc` at 2.2.1 (`main.py` verb list, `commands/connections.py`, `core/keychain.py`, `commands/auth.py`, `core/config.py` default scopes) · `ADR-008` §"tier-scoped credentials" and `inheritance-and-publish.md` §6 open #1 (the F16 credentials-carrier class) · vendor documentation cited inline in §3. |
| **Governing invariants** | #1 parse-never-compute (the CLI decides and authors every sentence; the app renders) · #4 security posture inherited and enforced, never weakened; trust roots compiled in · #5 route by actor-competence × reversibility · #6 one-way inheritance, secrets never travel in it, git is never a secret carrier. |
| **What is true today** | `cc` has no `connect` verb (`main.py` exposes `env`, `resolve`, `doctor`, `connections`, `freshness`, `update`, `repair` (ENGINE-BLOCKED stub), `deprovision`, `version`). `cc connections` reads state and cannot change it. `core/keychain.py` can write, but is called only by `cc auth` under service `com.everyoneneedsacopilot.copilot.github`. `team_scopes:` in the live org config is empty. Nothing in this document exists yet. |

---

## 1. The use case, in the owner's framing

Anyone in the company already proves who they are to GitHub every day: they are a member of the organization, they are on a team, and they have a working sign-in that Control Tower already drives through a device-code flow at wizard step 2. That single fact should be sufficient to get them everything else. Bob in accounting installs Control Tower on a new Mac, signs in with GitHub because that is the one thing the product already asks him to do, and his machine is provisioned against the organization's Infisical instance automatically — an identity created under his name, scoped to exactly the paths his teams entitle him to, written straight into his keychain by the CLI and never shown to him. No admin is in the loop, no ticket is filed, no approval is waited on, nobody hand-carries a Client ID or a Client Secret over Slack, and nothing appears on screen that a non-technical person could paste into the wrong window. When he leaves the accounting team, or leaves the company, the same GitHub act that removes his repository access removes his store access, because there was only ever one membership fact and one place it was checked.

**The job to be done, stated as a job rather than a feature:** *When my department's tools need a key I don't have and shouldn't have, I want the work to just run, so I can close the month without asking a colleague to DM me something I know I'm not supposed to have.*

---

## 2. Reframe — the assumption in the brief that has to be challenged

The brief says "use GitHub as the authentication method to connect to my Infisical setup." Read literally, that describes **federation**: Infisical trusts GitHub, Bob presents a GitHub credential to Infisical, Infisical decides. That is the right *intent* and it is the wrong *mechanism*, for one reason that governs this entire document:

> **GitHub is an OAuth 2.0 authorization provider for user login, not an OIDC identity provider that emits verifiable identity assertions to third parties — and even where a GitHub identity can be presented, GitHub does not export team membership as a claim. Infisical's GitHub sign-in proves *who someone is*. It says nothing about *which teams they are on*, which is the entire authorization question.**

So there is no configuration of Infisical and GitHub, at any licence tier, in which "being on the accounting team" flows into "may read `/departments/accounting`" without a third component in between. **Something must translate GitHub team membership into store authorization.** That translation is unavoidable. The only real design question — and this document's actual subject — is:

> **Does that translator *issue assertions*, or does it *dispense secrets*?**

Everything else follows from that answer, including the custody problem, the revocation model, the offboarding sweep, the audit story, and whether a laptop ever holds a store credential at rest. The owner's phrasing ("automatically create that username, Client ID, and Client Secret") describes the secret-dispensing shape. §5 recommends the assertion-issuing shape instead, delivers the identical experience, and states the deviation plainly.

**A second assumption worth naming:** the brief treats "no admin ceremony" as the goal. It is the *user-visible* goal. The operational goal underneath it is stronger and easier to verify: **the number of acts an admin must remember in order for offboarding to be complete must be exactly one, and it must be an act they were already going to perform.** A design that removes the provisioning ceremony but leaves a revocation ceremony has moved the burden to the place where forgetting it is a security incident rather than an inconvenience. That is the G-12 gap in one sentence, and it is the bar every option below is scored against.

---

## 3. What Infisical and GitHub actually support today

Accuracy matters more than optimism here, because two of the three architectures below are load-bearing on vendor capability. Each row carries a verification status: **Documented** (stated in vendor documentation reached during this research), **Reported** (consistent across secondary sources, confirm before budgeting), or **Assessed** (a conclusion drawn from the primary facts, not itself a vendor claim).

### 3.1 Infisical

| # | Capability | Status | What it means here |
|---|---|---|---|
| I-1 | **Universal Auth** machine identities: static `clientId` + `clientSecret` exchanged at `/api/v1/auth/universal-auth/login` for an access token | Documented; also confirmed in our own code (`cli-copilot/…/infisical/api_client.py:103-124`) | This is the rung the ladder uses today and the artifact the owner's phrasing names. |
| I-2 | **Client secrets are createable via API** with `ttl` and `numUsesLimit` — `POST /api/v1/auth/universal-auth/identities/{identityId}/client-secrets`; the plaintext secret is returned once in the response, and client secrets are individually revocable | Documented | Makes minting per-machine credentials mechanically possible, and makes them expirable and single-use — which matters for delivery-once semantics. |
| I-3 | **Access tokens are short-lived and renewable** (`accessTokenTTL`, `accessTokenMaxTTL`, `/api/v1/auth/token/renew`), and Universal Auth supports trusted-IP restriction on both client-secret use and access-token use | Documented | The read credential can be minutes-lived even when the underlying identity is long-lived. |
| I-4 | **OIDC Auth for machine identities**: an identity can be configured with `oidcDiscoveryUrl`, `boundIssuer`, `boundAudiences`, `boundSubject`, `boundClaims`, and authenticates by presenting a JWT at `/api/v1/auth/oidc-auth/login`; Infisical fetches the issuer's public keys and validates issuer, audience, subject and claims | Documented | **This is the pivot the recommendation turns on.** Any service that can publish a JWKS and sign a JWT can be a trusted issuer for a pre-configured identity — without ever holding an Infisical credential. |
| I-5 | Infisical publishes a **GitHub Actions** OIDC-auth guide and an `Infisical/auth-action`, i.e. the GitHub Actions OIDC token is a supported issuer shape | Documented | A scheduled reconciliation job in the org repo can authenticate to Infisical with no static secret at all. |
| I-6 | **Identity creation** (`POST /api/v1/identities`), project membership for identities, and **additional privileges** scoped to a specific secret path for machine identities | Documented (additional-privileges API is documented as identity-only, not user) | Path-level scoping per identity is real, which is what makes `team_scopes` implementable. |
| I-7 | **GitHub social sign-in** for user accounts on self-hosted (`CLIENT_ID_GITHUB_LOGIN` / `CLIENT_SECRET_GITHUB_LOGIN`, callback `/api/v1/sso/github`) is available without an enterprise licence | Documented for the env vars; **Reported** for the licence tier ("SSO beyond Google/GitHub requires Pro") | Proves *identity*. Carries **no** GitHub team or org membership. |
| I-8 | **SAML SSO / generic OIDC SSO** for user login require a paid tier on self-hosted; **SCIM and LDAP** require an Enterprise licence | Reported (Infisical SSO overview plus a third-party pricing teardown) — **confirm with Infisical before any commitment** | This prices Architecture A. Group-based access driven by an external IdP is the enterprise SKU, not the community build. |
| I-9 | Built-in **audit log**, queryable by user/identity/secret/environment/time, streamable | Documented (§1.6.1 of the ratified doc, from the 2026-07-07 evaluation) | Gives us the "which identity read which secret" half of the audit story. |
| I-10 | Infisical **does not** synchronize GitHub organization teams into Infisical groups | Assessed — no such feature appeared in any documentation reached | The translator is unavoidable. This is the finding §2 rests on. |

### 3.2 GitHub

| # | Capability | Status | What it means here |
|---|---|---|---|
| G-A | **SAML SSO for an organization requires GitHub Enterprise Cloud**; it is not available on Team | Documented | Architecture A's "one IdP in front of both" has a hard, priced prerequisite on the GitHub side as well as the Infisical side. |
| G-B | GitHub's user login is **OAuth 2.0**; it does not issue OIDC ID tokens to relying parties, and the device flow returns an opaque access token | Assessed from the absence of any user-facing OIDC issuer and from our own `commands/auth.py` device-flow implementation | The CLI cannot hand Infisical a GitHub-signed assertion about Bob. |
| G-C | GitHub Actions **does** issue OIDC tokens (`token.actions.githubusercontent.com`) with repository/workflow/ref claims | Documented (and I-5) | Workload identity is federatable; *user* identity is not. |
| G-D | A **GitHub App installation token** with the organization **Members: read** permission can read team membership (`GET /orgs/{org}/teams/{team_slug}/memberships/{username}`), and the Members permission is what a GitHub App needs to subscribe to team events | Documented | The authoritative membership lookup should use the **App's** token, not the user's — the user's token proves who they are; the App's token proves what they are entitled to. This separation matters and is used below. |
| G-E | An organization already has a registered GitHub App — `github_app.client_id: Ov23li2VmVUyOGXbwyDX` in the live `ecosystem.yml`, driving the wizard's device flow | Verified in live config and `commands/auth.py` | The trust anchor for all of this already exists and is already inherited through org config. No new app registration is required for the pilot. |
| G-F | The CLI's default requested scopes are `read:org repo write:public_key` (`core/config.py:149`) | Verified in code | The CLI is *already* authorized to register an SSH public key on the user's GitHub account. §5.3 uses this. |
| G-G | GitHub rejects registering an SSH public key that is already registered to another account | **Reported** — long-standing behaviour, **flag for the sec pass to confirm**, because §5.3's identity binding leans on it | Makes a registered public key a usable, globally-unique binding to one GitHub login. |

### 3.3 The conclusion this section forces

Architecture A as literally briefed — *"Infisical trusts the same identity provider as GitHub, so membership is access and there is nothing to mint"* — **cannot be built on GitHub alone**. It requires a *third* identity provider (Entra, Okta, Google Workspace, Keycloak, Authentik) that sits in front of both, which means GitHub Enterprise Cloud on one side (G-A) and an Infisical paid/Enterprise tier on the other (I-8), and *even then* the mapping from a GitHub team to an Infisical group is carried by SCIM or by IdP group claims — not by GitHub teams. An organization that runs its group model in GitHub teams and its IdP as a login front-end would still need a reconciler to keep the two in sync. That is not an argument against federation for a large enterprise; it is an argument that federation does not remove the translator, it relocates and prices it.

---

## 4. Three candidate architectures

Presented as three because the two in the brief collapse into a false binary once §3 is taken seriously: the honest spread is *federate*, *dispense*, or *assert*.

### 4.A True federation — Infisical and GitHub behind one identity provider

**Shape.** The organization runs an IdP (Entra ID, Okta, Google Workspace, Keycloak, Authentik). GitHub organization access is gated by that IdP via SAML SSO. Infisical user login is gated by the same IdP via SAML or generic OIDC SSO, with SCIM provisioning creating and deprovisioning Infisical users and mapping IdP groups to Infisical groups. Infisical groups carry project roles and path-scoped privileges. Bob logs into Infisical as *himself*; the CLI holds an Infisical user session rather than a machine credential. Membership is access, in the strongest sense: one directory, one grant, one revoke.

**Two sub-shapes, because they differ materially:**

- **A1 — full federation.** As above. Requires GitHub Enterprise Cloud (G-A) and Infisical paid/Enterprise (I-8). The org's group truth moves out of GitHub teams and into the IdP; GitHub teams become a projection of IdP groups rather than the source. This is a *company identity programme*, not a feature of this product.
- **A2 — GitHub sign-in plus a membership reconciler.** Infisical's free GitHub social login (I-7) authenticates Bob as himself, and an org-operated reconciler keeps Infisical group membership in step with GitHub teams via Infisical's API, driven by the GitHub App's `membership` and `organization` webhooks (G-D) with a scheduled sweep behind it. Cheap on the login side, and it delivers genuine per-person attribution in Infisical's audit log (I-9). **But** the reconciler needs a *user-and-group-management* credential at Infisical — the same custody class as 4.B's minting credential, arguably worse, since user management is a broader capability than identity minting. And it changes Bob's day one: he now needs an Infisical *user session* on his Mac, which means either a second browser sign-in (the North Star's whole point is that there isn't one) or a token the reconciler hands him, at which point A2 is 4.B wearing a different hat. Per-seat user pricing also applies where Infisical charges per user.

**What it cannot cover.** Headless and automation identities. CI jobs, scheduled agents, and any unattended process have no interactive human to federate, so machine identities (I-1/I-4) remain necessary for that class regardless. Federation shrinks the machine-identity population to genuinely-machine actors — which is the *correct* end state and a good outcome — but it does not empty it.

**What it means for the existing Universal Auth rung.** Rung 1 of the §1.6.3 ladder stops being "read a static pair from the keychain and log in as a machine" and becomes "resolve the current user's own session". `_NEVER_FROM_STORE` (the `managed_store.py` guard that makes bootstrap credentials structurally unable to live in the store they unlock) loses its subject for interactive use, and the permanent false-negative class that produced G-1 disappears at the root rather than being patched. The Universal Auth pair survives only for headless actors.

### 4.B Provisioning broker that mints — the owner's literal framing

**Shape.** A small org-operated service, co-located with Infisical on the organization's own infrastructure. `cc connect --provision` **[NEW]** proves the caller's GitHub identity to the broker; the broker resolves that login's team memberships authoritatively using the GitHub App installation token (G-D); it derives the entitled scopes from the inherited `team_scopes` map (§8); it calls Infisical to create an identity (I-6), attach Universal Auth, grant project membership and path-scoped privileges, and create a client secret with a short TTL and a use limit (I-2); it returns the `clientId` and `clientSecret` **once**, over the authenticated channel; and `cc connect` writes both straight into the macOS keychain under service `copilot-cli` (the accounts the ladder already reads at `secrets_ladder.py:47,112`) and **never renders, masks, truncates, logs, or echoes either value**. Bob sees a row change from a state to another state.

**The custody problem, stated without softening.** The broker holds a credential that can create identities and grant them project access. **An identity-minting credential is transitively a secret-reading credential**: anything that can mint an identity and grant it `/shared` read can mint one for itself. There is no Infisical role configuration that removes this — restricting the broker to "identity management only" does not help, because identity management *is* the grant power. So 4.B's broker is a **full-blast-radius component**, and it is exactly the F16 credentials-carrier class that `inheritance-and-publish.md` §6 open #1 calls "the single largest dependency" and that ADR-008 names as one of the three reasons `publish` is deferred. Building 4.B means standing up, hardening, monitoring, patching and eventually rotating a component whose compromise equals compromise of the store. That must be a deliberate decision, not a side effect of shipping a Connect button.

**Where it could live, honestly compared:**

| Home | Custody | Verdict |
|---|---|---|
| GitHub Actions workflow in the org repo, authenticating to Infisical by Actions OIDC (I-5/G-C) | No static secret anywhere; audit trail is the workflow run log; bound claims pin it to one repo, workflow and ref | **Excellent for scheduled sweeps, unusable for user-initiated provisioning** — triggering a workflow requires repository write or a dispatch token, and consumers are read-only by design (invariant #6). Do not contort the trigger; use it for what it fits. |
| Small HTTP service beside Infisical on the org's Coolify host | Holds an Infisical identity-admin credential in the host's own secret manager; needs TLS, patching, uptime, rate limiting, its own audit log | **The only workable home for on-demand provisioning in 4.B.** It is a new always-on org component with store-equivalent blast radius. |
| A GitHub App backend | Same as above plus the App's private key; the App identity is genuinely useful (G-D) but does not change where the Infisical credential lives | Same custody, more moving parts. The App is needed *anyway* for membership lookup — but it should not be the reason to build a minting service. |

**Naming convention for minted identities.** `ct:<github-login>:<machine-short-id>`, e.g. `ct:bob-alvarez:7f3a91`. The machine id is a random UUID generated once by the CLI and stored locally — **not** the hardware UUID or serial (it changes on a logic-board swap, it is weakly PII, and it should not be exportable to a service). Human-readable context goes in identity metadata, never the key: `{github_login, machine_name: "Bob's MacBook Air", provisioned_at, broker_version, teams_at_mint: [accounting], scopes_at_mint: [...]}`. `teams_at_mint` is what makes the reconciliation sweep (§6.6) able to detect drift without re-deriving history.

**Lifecycle burden.** Every minted identity is an object with a life: it must be listed, re-minted for a second Mac, revoked on machine loss, revoked on team change, revoked on offboarding, and swept for orphans. **All six of those are new operations that exist only because the credential is long-lived.** That observation is the entire argument for 4.B′.

### 4.B′ Provisioning broker that asserts — recommended

**Shape.** The same broker, doing the same GitHub verification against the same `team_scopes` map, but it **never calls Infisical and never holds an Infisical credential**. Instead:

1. The admin creates, **once, by hand at the Infisical console**, one machine identity per entitled scope — `enac-shared-reader`, `enac-accounting-reader` — each granted exactly the project, environment and path from `team_scopes` (I-6), each configured with **OIDC Auth** (I-4) whose `oidcDiscoveryUrl` points at the broker, with `boundIssuer` = the broker, `boundAudiences` = the org's Infisical instance, and `boundClaims` requiring the scope claim that identity corresponds to.
2. The broker publishes a JWKS at its own `/.well-known/` endpoint and holds exactly one secret: **its own signing key**, which never leaves its host and grants nothing on its own.
3. `cc connect` **[NEW]** proves the caller's GitHub identity (§5.3), the broker resolves teams via the App installation token (G-D), maps them through `team_scopes`, and returns a **short-lived JWT** (minutes) whose `sub` identifies the person and machine (`github:bob-alvarez:machine:7f3a91`) and whose scope claim names the entitled scope.
4. The CLI presents that JWT to Infisical at `/api/v1/auth/oidc-auth/login` and receives a short-lived Infisical access token (I-3), which it uses for that invocation.

**Why this is structurally different, not merely tidier:**

- **The broker cannot read a secret and cannot grant itself one.** It can only assert claims that pre-existing, admin-created identities are already bound to. A compromised broker can impersonate entitled users for the duration of the compromise — serious, and named in §7 — but it cannot create a new scope, cannot widen an existing one, and cannot exfiltrate the store wholesale. This is the difference between a component with store-equivalent blast radius and one with user-impersonation blast radius, and it is an *impossible-by-construction* argument of exactly the kind invariant #6 is built from.
- **Nothing store-related is ever at rest on the laptop.** No `clientId`, no `clientSecret`, nothing in the keychain under `copilot-cli` for the store at all. The only credentials on Bob's Mac are the ones he already has for GitHub. **`_NEVER_FROM_STORE` stops being a paradox** because there is no bootstrap credential to exempt.
- **Revocation needs no revocation.** Every access requires a fresh assertion, and every assertion requires a live GitHub membership check. Remove Bob from the accounting team and his next mint fails. The maximum exposure window is the Infisical access-token TTL plus any local cache window — a number the admin sets, not a memory the admin keeps. **This closes G-12 by construction rather than by discipline**, and it collapses the six lifecycle operations of 4.B down to two (see §6).
- **Machine loss has one lever.** With no store credential on the device, the thing to kill is the GitHub credential — which is also the thing to kill for repository access. One act, not two.

**What it costs.** The broker is still a new always-on org component, still needs TLS, uptime, rate limiting and patching, and now sits on the **hot path of every store read** rather than on a once-per-machine provisioning path — so its availability becomes a runtime dependency, mitigated by an access-token cache with a bounded TTL (§6.3) and an honest degrade (§7 E-6). It also asks the admin to do a one-time console setup that is more conceptually demanding than "paste a URL": creating per-scope identities and registering an OIDC issuer. That is a real onboarding cost, and §8's `team_scopes` map is what lets Control Tower generate the exact checklist rather than leaving the admin to invent it.

### 4.4 Three Lenses

| | **A1 full federation** | **A2 GitHub login + reconciler** | **B mint** | **B′ assert** |
|---|---|---|---|---|
| **Desirable** — would a user choose this? | **High.** Zero credential moments; his existing company sign-in is the whole story. | **Medium.** A second sign-in surface at Infisical, or a token handed to him — which is B in disguise. | **High.** Zero credential moments on screen; the value never appears. Identical *felt* experience to B′. | **High.** Identical to B from Bob's side. Slightly better under failure: no half-provisioned state exists. |
| **Feasible** — can we build and maintain it? | **Low.** GitHub Enterprise Cloud (G-A) + Infisical paid/Enterprise (I-8) + SCIM group mapping + a company IdP programme. Out of reach for the pilot org and for most target orgs. | **Medium.** Cheap login, but the reconciler carries a *user-management* credential — a worse custody class than B's — and per-seat cost. | **Medium.** Everything needed is documented API (I-2, I-6). The hard part is not the code, it is standing up a component with store-equivalent blast radius. | **Medium.** Needs I-4 exactly as documented, a JWKS endpoint, and a one-time admin console setup. Less code than B; more precision required in the trust configuration. |
| **Viable** — does it make business sense? | **Low now, high at scale.** Correct destination for an enterprise that already runs an IdP; unjustifiable as a prerequisite for a product whose promise is that a small org can self-host this. | **Low.** Buys per-person attribution at the price of the worst custody class and a per-seat bill. | **Medium.** Ships the owner's framing literally, and creates six permanent lifecycle operations plus a component whose compromise is total. | **High.** One new component, one secret (its own signing key), two lifecycle operations, offboarding correct by construction, and the store's blast radius unchanged from today. |
| **Closes G-12 (offboarding actually revokes)?** | Yes, by directory. | Yes, at reconciler latency. | **No** — only by a sweep the admin must operate correctly. Revocation is a second act in a second system. | **Yes, by construction.** No sweep is required for correctness. |

---

## 5. Recommendation

### 5.1 The call

**Target: 4.B′ — the broker asserts, it does not dispense.** Build the GitHub-verified broker, but make it an OIDC issuer that Infisical already trusts, not a client that holds Infisical's keys.

**Is 4.B a stepping stone to it? No — and this is the load-bearing judgement.** 4.B and 4.B′ share the *hard* half (GitHub App membership verification, the `team_scopes` map, the CLI verb, the app surface, the copy, the failure routing) and differ in the *easy* half (what the broker returns and what the CLI does with it). Building 4.B first therefore does not de-risk 4.B′; it only adds the thing 4.B′ exists to avoid — an identity-admin credential in an always-on service, plus six lifecycle operations, plus the offboarding sweep, all of which would then have to be *decommissioned*. That is precisely the "pipeline built for nobody" the trace's own sequencing note warns against. **Build the shared half once, and terminate it in an assertion.**

**Is 4.A a stepping stone? Also no — it is the destination past the destination.** 4.A is the right answer for an organization that already runs an IdP and already pays for GitHub Enterprise Cloud, and 4.B′ is designed to be *replaceable* by it: when an org federates, the broker's per-scope identities are retired in favour of IdP-driven groups, and nothing on Bob's machine changes, because nothing on Bob's machine was ever store-specific. Keep 4.A as a documented supported configuration for orgs that have it, not as a prerequisite. **State this in the product's own words: the store must answer to the organization's GitHub team membership; how it does so is the organization's choice, and Control Tower ships one working answer.**

**Where 4.B survives:** headless and automation actors (CI, scheduled agents, the reconciliation sweep itself) legitimately need long-lived machine identities. Those are minted **by an admin, by hand, deliberately** — not self-serviced. The self-service path is for humans, and humans get assertions.

### 5.2 What each architecture's CLI and app surface looks like

Consistent with the existing verbs: `cc connections --json` stays the read; `cc connect` **[NEW]** becomes the act. Under invariant #1 every sentence below is CLI-authored and rendered verbatim; the app computes nothing.

| | **4.B (mint)** | **4.B′ (assert) — recommended** |
|---|---|---|
| **Provision** | `cc connect --provision --json` **[NEW]** — proves identity, receives a pair, writes the keychain, verifies with a real read, returns `{result, scopes[], machine_id, identity_name}` with **no credential fields in the schema at all** | `cc connect --json` **[NEW]** — proves identity, registers this machine, verifies end-to-end by performing one real assertion-and-read, returns `{result, scopes[], machine_id}`. Nothing is written to the keychain for the store. |
| **Steady state** | Ladder rung 1 reads the keychain pair, logs in, reads the secret | Ladder rung 1 mints an assertion (or reuses a cached access token within TTL), logs in, reads the secret |
| **List** | `cc connect --list-machines --json` **[NEW]** — "these Macs have access" | Same verb, same output shape — but the list is *registrations*, not credentials, so listing is informational rather than a security surface |
| **Re-provision (new laptop)** | Run the same verb; a second identity is minted; the first is untouched | Run the same verb; a second machine id registers; nothing is minted |
| **Revoke one machine** | `cc connect --revoke <machine-id> --json` **[NEW]**, plus an admin panel row; must call Infisical | `cc connect --forget <machine-id>` **[NEW]** removes the registration; the authoritative act is revoking the GitHub credential, which is the same act as for repository access |
| **App surface** | One row, one action, shown only when the CLI reports it is actionable by this person. No value ever displayed | **Ideally no row at all.** Provisioning happens inside the existing "Getting your team's shared keys ready" stage, and step 6 shows a receipt. A row appears only when something is *not* available, and then it is a fact with a named human, never a button |
| **Admin surface** | Requests/identities panel, revoke actions, orphan warnings | `cc store verify --json` **[NEW]** — proves the store really does answer to team membership *before* the admin screen is allowed to say "Connected", which is the walkthrough's day-zero **[NEW]** promise made real |

**The verb name matters.** `cc connect` reads as "connect me", which is what Bob would say. It should never require, accept, or prompt for a pasted value in any mode — if a future flag would take one, that flag belongs to an admin verb, not this one.

### 5.3 How the CLI proves who it is, without shipping a bearer token to the broker

The broker needs proof of GitHub identity. Three options, in preference order:

1. **SSH key challenge-response — recommended.** At first run the CLI generates a keypair on-device and registers the public key on the user's GitHub account using the device-flow token — which it is **already scoped to do** (`write:public_key`, G-F), titled legibly (`Copilot Control Tower — Bob's MacBook Air`). Thereafter the CLI proves identity by signing a broker-issued nonce; the broker fetches `https://github.com/<login>.keys`, verifies the signature, and then asks the **App installation token** for authoritative team membership (G-D). **No bearer token ever leaves the machine.** The private key is the machine's identity, it is per-machine by construction, it doubles as the git credential path §6.1 of the ratified doc already provisions for authors, and deleting it from GitHub kills repository access and store access in one act. Depends on G-G (global key uniqueness) — **flagged for the sec pass**.
2. **Present the user-access token over TLS.** Simplest, and it makes the broker a bearer-token sink: it must use the token for `GET /user` only, hold it in memory only, zeroize it, never log it, and never persist it. A compromised broker can impersonate every user who provisions during the compromise window. Acceptable as a fallback, named as a residual (§7 E-3).
3. **A second device flow run by the broker.** Rejected: it puts a second sign-in in front of Bob on day one, which is the exact experience the North Star exists to delete.

---

## 6. Service blueprint — the recommended path, frontstage and backstage

Frontstage is what Bob or the admin perceives. Backstage is what must exist for it to be true. Failure points are named where they originate, which is overwhelmingly backstage.

### 6.1 Day zero — the admin stands the store up

| | |
|---|---|
| **Frontstage** | Admin pastes the store URL and names the teams. Control Tower **proves the claim before making it**: `Connected. Anyone on the teams you named gets these keys automatically.` — or, when it cannot: `I couldn't confirm this store hands out keys by team, so I won't say it's connected.` |
| **Backstage** | `cc store verify --json` **[NEW]** does a live end-to-end proof, not a reachability ping: mint a test assertion for a synthetic scope, exchange it at `/api/v1/auth/oidc-auth/login`, confirm a scoped read succeeds and an *unentitled* read fails. Both halves are required — a positive-only test cannot distinguish "correctly scoped" from "everything is readable". |
| **Backstage setup, one time, by hand** | Per-scope Infisical identities created at the console (I-6); OIDC Auth configured on each with the broker's discovery URL, bound issuer, audience and scope claim (I-4); broker deployed with TLS beside Infisical; broker signing key generated on-host; GitHub App granted **Members: read** and subscribed to `membership` / `organization` events (G-D); `team_scopes` written into the org tier's inherited config and pushed (§8). |
| **Failure points** | OIDC trust misconfigured so *any* claim validates (catastrophic, and precisely what the negative half of the verify catches) · bound audience omitted, making assertions replayable across instances · `team_scopes` written but not published, so consumers inherit an empty map and fail closed with an unhelpful sentence · the App installed without Members: read, so every membership lookup returns "not a member" and every user is silently unentitled. |
| **Transition out** | The admin's next act is *nothing*. That is the design target: adding a person to a GitHub team is the whole provisioning event, and the setup screen should say so in those words. |

### 6.2 Day one — Bob provisions himself

| | |
|---|---|
| **Frontstage** | Step 2: the GitHub device code he already does. Step 8: a stage named `Getting your team's shared keys ready`. Step 6: a receipt listing what his team has set up, no buttons on shared rows. He is never told a credential exists. |
| **Backstage, in order** | `cc auth` token present → CLI generates its machine keypair and registers the public key (G-F), or reuses the existing one → CLI requests a nonce, signs it, posts `{login, machine_id, signature, machine_name}` → broker verifies the signature against `<login>.keys` → broker resolves org membership and team list with the **App installation token** (G-D) → broker maps teams through the inherited `team_scopes` (§8), unioning entries, failing closed on unknown teams → broker returns a short-lived JWT per entitled scope → CLI exchanges at Infisical (I-4), receives a short-lived access token (I-3), performs **one real read** to prove the whole chain, discards the token or caches it within its TTL bound → CLI returns the structured result and the CLI-authored sentence. |
| **What is written to disk** | The machine keypair (private key protected by the keychain) and a non-secret registration record `{machine_id, machine_name, registered_at, scopes_last_seen[]}`. **Nothing store-derived.** |
| **Failure points** | Broker unreachable (§7 E-6) · user in no entitled team (E-4) · the *sequencing* defect the walkthrough already named: step 6 asks about connections before step 8 has materialized org config, so the store endpoint and `team_scopes` are not yet on the machine. **This design does not fix that on its own and must not pretend to** — either step 6 moves after materialization, or it speaks only about what is knowable at that moment. |
| **Transition, designed** | The handoff from "signed in to GitHub" (step 2) to "your keys work" (step 8) is invisible and asynchronous. It must be *idempotent and resumable*: if the wizard is closed between them, the next launch re-runs the same verb and reaches the same state without a second registration and without a duplicate SSH key. |

### 6.3 Steady state — every subsequent read

| | |
|---|---|
| **Frontstage** | Nothing. Bob asks his copilot for last month's close and it answers. He never learns the word Infisical. |
| **Backstage** | Ladder rung 1 checks for a cached Infisical access token within TTL; on miss, mints a fresh assertion and exchanges it. Process-lifetime use only for the secret value itself, exactly as §1.6.3 already requires. |
| **The one tunable that matters** | The access-token cache window. Short means a broker outage is felt quickly and a stolen unlocked machine has a small window; long means resilience and fewer round trips. **Recommendation: cache within the Infisical `accessTokenTTL` only, no independent cache lifetime**, so there is exactly one number to reason about and it is set at the store, in inherited config, by the admin — never locally. |
| **Failure points** | Broker outage on the hot path (the real cost of B′) · clock skew invalidating assertions · a team removal that has not yet propagated, bounded by the same TTL. |

### 6.4 Deviations from the ratified §1.6 that must be ratified or rejected

1. **§1.6.3 rung 1 is re-specified.** The ratified text describes rung 1 as resolving via "the CLI's machine identity/service-token … by their own GitHub-team membership". This design keeps the *intent* exactly and changes the *mechanism*: there is no machine identity or service token on the device; there is a per-invocation assertion. This is stricter than the ratified text, not weaker, and it deletes the bootstrap-credential paradox the ratified text implicitly created. **Deviation, upward.**
2. **§1.6.2 step 3's "point it at the same IdP already gating GitHub SSO" is not achievable with GitHub alone** (§2, §3.3). The ratified sentence assumes a federation that GitHub does not offer for user identity. This design substitutes "a broker that reads GitHub team membership authoritatively and asserts it to the store" and keeps the ratified *property* — one source of truth for tier membership — intact. **Deviation, mechanism-only, and §1.6.2 step 3 should be amended to say so rather than left as an unbuildable instruction.**

### 6.5 Lifecycle operations, complete

| Operation | 4.B′ (recommended) | 4.B, for contrast |
|---|---|---|
| **Provision** | Register a machine; nothing minted | Mint identity + UA + client secret; write keychain |
| **List mine** | List registrations (informational) | List identities (security surface — each row is live access) |
| **Re-provision (new laptop)** | New registration, automatic on first run, no admin | New identity per machine; admin sees the population grow |
| **Machine loss** | Delete that machine's SSH key from GitHub (one act, kills repo + store); optionally `--forget` the registration | Revoke the client secret **and** the identity **and** the SSH key — three acts, two systems |
| **Team change** | Nothing. The next mint reflects the new membership within one TTL | Sweep must detect and re-scope or revoke |
| **Offboarding** | Remove from the org/team on GitHub. Done. Access dies within one TTL | Remove from GitHub **and** revoke every identity that person holds across every machine |
| **Orphan cleanup** | Registrations only; cosmetic | Identities; a missed one is live access |

### 6.6 Offboarding reconciliation — event-driven or scheduled? Pick one and justify

**Both, with the scheduled sweep as the authority and the webhook as a latency optimization — and in 4.B′ neither is required for correctness.**

Justification, in that order: webhooks are best-effort. GitHub retries, but deliveries are missed when the receiver is down, when a payload is dropped, when the App's subscription is edited, and when someone changes membership through a path that does not fire the expected event. **A design whose security depends on receiving an event is a design that fails silently when it does not.** So the sweep — a scheduled GitHub Actions workflow in the org repo, authenticating to Infisical by Actions OIDC (I-5/G-C) with no static secret — is the authority: it enumerates entitled state, compares it to actual state, and reports or repairs drift. The webhook exists so the common case is fast, not so the guarantee holds.

In 4.B′ the sweep has no revocation work to do, because there is nothing standing to revoke; its job shrinks to **drift detection as an assurance control**: are there identities at Infisical that `team_scopes` does not explain? Is any identity configured with an OIDC trust that is not the current broker? Has any per-scope identity acquired a privilege wider than its `team_scopes` entry? Those are exactly the questions a quarterly access review asks, and answering them on a cron is strictly better than answering them in a spreadsheet. **That is the honest, and sufficient, reason to build the sweep even under the architecture that does not need it.**

### 6.7 Audit trail

Three logs, one correlation key:

| Log | Answers | Retention owner |
|---|---|---|
| **Broker log** | Who asked, from which machine id, which teams the App reported, which scopes were matched, what was asserted, TTL, and every *denial* with its reason | Org IT. This is the per-person attribution record. |
| **Infisical audit log** (I-9) | Which identity authenticated and which secret path was read, when | Org IT, streamed to wherever logs already centralize (§1.6.2 step 5) |
| **GitHub audit log** | Team membership changes, App installation changes, SSH key additions and removals | GitHub |

**The correlation key is the machine id**, which must appear in the assertion `sub` so it lands in Infisical's record of the authentication, and in the broker's log line. **Named residual, carried from §1.6.5:** with per-scope identities, Infisical's own log attributes reads to `enac-accounting-reader`, not to Bob — per-person attribution lives in the broker log and is only reconstructible by joining two logs on the machine id and a timestamp window. Per-user-machine identities (4.B) would put attribution directly in Infisical's log. **That is 4.B's one genuine advantage over 4.B′ and it should be stated whenever the two are compared.** If per-person attribution inside Infisical is a hard requirement, the mitigation is to mint one identity per *person* (not per machine) whose OIDC trust binds `boundSubject` to that person's login — a hybrid that keeps assertions on the wire and puts names in the store's log, at the cost of reintroducing a per-person object with a lifecycle. **Flagged for the sec pass as an open sub-decision.**

---

## 7. Edge cases and protections

**This section is structured for extension.** IDs are stable; the security review appends `E-nn` rows and fills the Residual and Owner columns rather than rewriting prose. Every row must end with a named actor — the honesty floor forbids a state whose only instruction is to try again.

| ID | Situation | What could go wrong | Protection (4.B′ recommended) | Protection (4.B, if built) | Residual | Owner |
|---|---|---|---|---|---|---|
| **E-1** | **Lost or stolen machine** | Whoever holds the disk reads the store | Nothing store-related is at rest. Kill the machine's SSH key on GitHub — one act, kills repo and store together. Bounded by access-token TTL | Client secret and identity must be revoked at Infisical, *and* the key removed. Two systems | Unlocked, running machine within cache TTL. FileVault and screen lock are the org's controls, not this product's | Admin |
| **E-2** | **Replayed provisioning request** | An intercepted request is replayed to obtain access | Broker-issued single-use nonce with short expiry, signature over `{nonce, login, machine_id, audience}`, TLS-only, `boundAudiences` on the Infisical side so an assertion for one instance is worthless at another | Same, plus delivery-once semantics on the client secret (`numUsesLimit`, short `ttl` — I-2) so a replayed *delivery* yields a spent secret | Attacker with the private key is the user, by definition. Detection is the broker log's per-machine anomaly, not prevention | Sec review |
| **E-3** | **Broker sees a user bearer token** (only if §5.3 option 2 is used) | Broker becomes a token sink; compromise enables impersonation | Prefer §5.3 option 1 — no bearer token is transmitted at all | Memory-only, zeroized, never logged, never persisted; `GET /user` only | If option 2 ships, a compromised broker impersonates every user who provisions during the window | Sec review |
| **E-4** | **User is in no entitled team** | A dead end, or worse, a silent grant | Fail closed. The CLI authors: `Your team hasn't made this available to you.` plus a named human and the note-to-admin composer. **Never** a Connect button, never a decline (a decline implies he asked) | Same | Distinguishing "no entitlement" from "misconfigured `team_scopes`" needs the broker to say which, and the CLI to render two different sentences | Design + sec review |
| **E-5** | **User removed mid-session** | Access persists after removal | Next mint fails; exposure bounded by access-token TTL. Copy distinguishes *removed* from *unreachable* — different actors, never the same sentence | Access persists until a sweep revokes. **This is the G-12 gap, unfixed** | The TTL window itself. Set at the store, in inherited config | Admin sets TTL; sec review sets the bound |
| **E-6** | **Broker unavailable** | Every read fails; in B′ it is on the hot path | Honest degrade, named actor, no dead end: `Your team's shared connections can't be reached right now. Nothing on this Mac changed, and I'll keep checking.` → escalating to `…this one belongs to whoever looks after your Mac.` with the shipped **Copy details for support** affordance. Cached token keeps work running within TTL | Provisioning fails; already-provisioned machines are unaffected — B's one resilience advantage | Cold-start during an outage cannot be worked around. Named, not hidden | Control Tower, then IT |
| **E-7** | **Rate and abuse limits** | Enumeration of logins, mint flooding, denial of service | Per-login and per-IP rate limits, idempotency per `(login, machine_id)` so repeats return the existing state rather than minting, global circuit breaker, uniform timing and identical responses for "not a member" and "unknown login" so the endpoint is not a membership oracle | Same, plus a hard cap on identities per login with admin alerting above it | Thresholds are unset. **Sec review to specify** | Sec review |
| **E-8** | **Compromised broker** | Impersonation (B′) or total store compromise (B) | B′ bounds it structurally: no Infisical credential, cannot create or widen a scope. Signing key on-host only; key rotation runbook; JWKS rotation with overlap | **Unbounded.** Identity-minting is transitively secret-reading (§4.B) | Even in B′, impersonation of every entitled user for the compromise window. Detection is drift sweep + broker log review | Sec review |
| **E-9** | **Retiring the org-wide admin pair** | The current single `INFISICAL_CLIENT_ID`/`_SECRET` with full `/shared` read stays alive as a shadow path | Sequenced, verified at each step: (1) populate `team_scopes` and create per-scope identities; (2) stand up the broker; (3) **the owner's own machine re-provisions through the same self-service path as everyone else** — dogfood before demolition; (4) confirm via Infisical's audit log that nothing has authenticated with the old pair for a full cycle; (5) revoke its client secret; (6) delete the identity; (7) remove the two names from `cli.overlay.yml:157-159` so `cc connections` stops naming them and G-1's false-negative class disappears at the root | Same sequence | Step 4's "full cycle" needs a stated duration | Owner |
| **E-10** | **Multi-org future** | One person in two orgs; credentials and scopes collide | The keychain account key is currently the bare secret **NAME** under service `copilot-cli` (`secrets_ladder.py:47,112`). **This collides across orgs and must become `<org>/<NAME>` before any second org exists.** Registrations, machine ids and `team_scopes` are all resolved per-org from the inherited config, which already carries `org:` | Same collision, and worse: two client-secret pairs under one account key | Migration of existing keychain entries is a one-way change needing a compatibility read | Design + sec review |
| **E-11** | **Bootstrap paradox** | The first admin and the first machine cannot self-serve from a system that does not exist yet | **The documented manual path remains the root of trust, and this is correct rather than a gap.** A human admin, at the Infisical console, authenticated as themselves, creates the per-scope identities and registers the broker's OIDC trust. The broker's signing key is generated on its own host and never transits. The chain terminates in a person at a console, exactly as every trust chain must. The product's job is to make that path *documented, short and verifiable* (`cc store verify` proves the result), not to eliminate it | Same, plus the first minting credential must be created and stored by hand | The runbook does not exist yet (G-8). **Blocking for a live run, not for this design** | Owner + docs |
| **E-12** | **`team_scopes` misconfiguration** | A path typo silently grants nothing, or a wildcard silently grants everything | Fail closed on unknown teams; no wildcards and no deny rules in the schema (§8); `cc store verify` tests a negative as well as a positive; the sweep flags any identity privilege wider than its `team_scopes` entry | Same | Schema validation location — CLI or broker or both — is undecided | Design |
| **E-13** | **SSH key binding assumptions** | If the same public key can sit on two GitHub accounts, identity binding breaks | §5.3 option 1 depends on G-G. Broker additionally confirms org membership via the App token, so a key-confusion attack still fails the entitlement check | n/a | **G-G is Reported, not verified. Sec review must confirm** | Sec review |
| **E-14** | *(reserved for the security review)* | | | | | |

---

## 8. What fills `team_scopes` — the shape, plus an illustrative ENAC mapping

The live org config has `team_scopes:` with no entries (verified in `~/.claude/ecosystem.yml`), which is G-9. Everything in `store:` is non-secret by construction and travels through inherited org config exactly as §1.6.2 step 6 requires — team slugs and secret paths are not secrets, and a machine that inherits a scope it is not entitled to simply fails the entitlement check.

**Proposed shape [NEW]:**

```yaml
store:
  type: infisical
  endpoint: https://secrets.ineedacopilot.com
  workspace_id: "458e8f7a-3d53-4e72-9d1c-718956463e2f"
  environment: prod
  secret_path: "/shared"        # retained for back-compat; superseded by the `everyone` entry
  team_scopes:
    - team: everyone            # reserved slug: any verified member of `org:` above
      environment: prod
      secret_path: "/shared"
      access: read
    - team: accounting          # a GitHub team *slug* within `org:` above
      environment: prod
      secret_path: "/departments/accounting"
      access: read
```

**Illustrative only — this is a worked example for ENAC, not a ratified configuration.** ENAC today has one department (`accounting`, `topology: separate`) and one store path (`prod:/shared`).

**Decisions embedded in the shape, each with its reason:**

| Decision | Reason |
|---|---|
| Keyed by GitHub **team slug**, resolved within the `org:` already at the top of the file | One source of truth for membership (§1.6.2 step 3). Slugs, not display names, because display names are renameable and slugs are what the API takes (G-D) |
| `everyone` is a **reserved slug** meaning "verified member of the org" | Makes the base `/shared` grant an ordinary row instead of a special case, so there is one code path and one place to audit |
| `access` is an enum, and **`read` is the only value self-service may grant** | Write access to a shared store is not a thing a person should be able to grant themselves by joining a team. If write is ever needed it is an admin act on a named identity |
| **Union across entries, no precedence, no deny rules** | A person on two teams gets both scopes. Deny rules invite ordering bugs and a false sense of containment; to remove access, remove the team entry or the membership |
| **Unknown team ⇒ no grant** (fail closed), and **no wildcards in `team:` or `secret_path:`** | E-12. A typo must produce nothing, loudly, rather than something, quietly |
| `environment` and an optional per-entry `workspace_id` are explicit | Orgs with more than one Infisical project or a non-`prod` environment are ordinary, not exceptional |
| The map is what generates the admin's setup checklist | Each entry corresponds 1:1 to one Infisical identity the admin creates once (§6.1). The product can therefore *show* the admin exactly what to create and then verify it, instead of describing it |

---

## 9. Bob's experience delta on the walkthrough-15 screens

Step 6 stops being a form and becomes what the walkthrough already drew as the North Star: **a receipt that is now true for every entitled person rather than aspirational** — shared rows read `Ready` with no button because being on the accounting team *is* the access, personal rows carry only his own sign-ins, and the "Available to connect" card has no reason to render because the *yours-but-not-connected* state cannot occur. The claim-code flow in §4 of the walkthrough — the `4TQ9-KMD2` sheet, the admin's Requests panel, the six pending/stale/declined/approved-but-undelivered states — becomes **unnecessary for every interactive user** and should be marked as such rather than built; it survives, if at all, only as the shape for an admin minting a headless automation identity, where a human approval genuinely belongs. The step 8 stage keeps its honest name, `Getting your team's shared keys ready`, and finally earns its promotion out of the completion-rule exemption, because a stage that can now genuinely succeed must be allowed to genuinely fail. Step 9's "Still to do" card disappears in the entitled case. And the failure vocabulary the walkthrough drafted survives verbatim and unchanged — `can't be reached right now… I'll keep checking` for an outage, `your access was turned off` for a removal, `your team hasn't made this available to you` for an unentitled service — because §7's whole point is that these three remain three different situations with three different next actors, no matter which architecture wins.

---

## 10. What this document does not settle

1. **Per-person attribution inside Infisical's own audit log** (§6.7) — per-scope identities put the name in the broker's log only. The per-person-identity hybrid is sketched and not chosen.
2. **The broker's uptime posture** — B′ puts it on the hot path. No SLO, no degraded-mode budget, no cache-TTL number is proposed here beyond "bind it to the store's own token TTL".
3. **Infisical licence tier facts (I-7, I-8)** are Reported, not confirmed. Confirm with Infisical before any commitment that depends on them.
4. **G-G (GitHub SSH key global uniqueness)** underpins §5.3 option 1 and is Reported, not verified.
5. **The step-6 sequencing defect** (§6.2) is a wizard-ordering problem this design neither causes nor fixes.
6. **The bootstrap runbook (G-8)** does not exist. E-11 says what it must contain; someone still has to write it.
7. **Rate-limit thresholds, key-rotation cadence, and JWKS overlap windows** (E-7, E-8) are named and unspecified — the security review's to fill.

---

## Sources

- Infisical — [OIDC Auth for machine identities](https://infisical.com/docs/documentation/platform/identities/oidc-auth) · [OIDC Auth: GitHub](https://infisical.com/docs/documentation/platform/identities/oidc-auth/github) · [Universal Auth](https://infisical.com/docs/documentation/platform/identities/universal-auth) · [Create Client Secret](https://infisical.com/docs/api-reference/endpoints/universal-auth/create-client-secret) · [Renew Access Token](https://infisical.com/docs/api-reference/endpoints/universal-auth/renew-access-token) · [Machine Identities](https://infisical.com/docs/documentation/platform/identities/machine-identities) · [Additional Privileges](https://infisical.com/docs/documentation/platform/access-controls/additional-privileges) · [SSO Overview](https://infisical.com/docs/documentation/platform/sso/overview) · [GitHub SSO](https://infisical.com/docs/documentation/platform/sso/github) · [Infisical/auth-action](https://github.com/Infisical/auth-action)
- Pricing/licence tiering (secondary, treat as Reported) — [Infisical Pricing Teardown 2026](https://dev.to/beton/infisical-pricing-teardown-2026-1ang)
- GitHub — [Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app) · [REST API endpoints for team members](https://docs.github.com/en/rest/teams/members) · [Preparing to enforce SAML single sign-on in your organization](https://docs.github.com/en/organizations/managing-saml-single-sign-on-for-your-organization/preparing-to-enforce-saml-single-sign-on-in-your-organization) · [Generating a user access token for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
