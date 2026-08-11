# Integration Auth Research — What "True Integration" Looks Like Per Platform

**Status:** research clarity doc · 2026-07-16
**Question answered:** for the platforms organizations most commonly connect, what does real, vendor-supported sign-in from a **native desktop app** look like in 2026 — and what should Control Tower's Integrations experience therefore honestly promise?
**Verdict up front:** the owner's suspicion is correct, and it is not a compromise — it is the standard. **No serious platform wants a native app to embed its sign-in UI.** The vendor-supported pattern everywhere is: *link out to the provider's real page in the user's own browser, get the token back through a standards-defined channel, store it in the OS keychain.* That is RFC 8252 ("OAuth 2.0 for Native Apps"), and it is exactly the architecture Control Tower already committed to (app renders, `cc` CLI owns OAuth + the keychain write, app holds no secret — see the frozen M3 sign-in seam).

---

## 1. Executive summary (plain language)

**Feasible, and first-class:**

- **Embedded provider sign-in is not just infeasible — it is anti-recommended.** Google actively blocks OAuth from embedded webviews; every provider's native-app guidance says "use the system browser." An app that embedded sign-in would look *less* trustworthy, not more integrated. Link-out is the honest and the correct design.
- There are exactly **two standard mechanisms** for getting the resulting token back to a native app without the app holding a `client_secret`:
  1. **Device Authorization Grant ("device flow", RFC 8628)** — the app shows a short code, the user approves at a provider URL in any browser, the app (via the CLI) polls until authorized. No local listener, no redirect handling, works over SSH. This is what `gh` CLI uses.
  2. **Authorization-code + PKCE with a loopback redirect (RFC 8252)** — the CLI opens the browser and listens once on `http://127.0.0.1:<ephemeral-port>`; the provider redirects the browser back to that loopback address with the code; the CLI exchanges it (PKCE proves it's the same client, no secret needed). One click, no code-typing.
- **Every platform we need has at least one of these paths** — but not always against its raw API:
  - **GitHub** — device flow, secret-free. Confirmed. (PKCE exists since July 2025 but GitHub still demands the client secret at token exchange, so device flow is the *only* secret-free GitHub path.)
  - **Google Workspace** — PKCE + loopback is the documented Desktop-app flow. Device flow is a dead end (its scope allowlist excludes Gmail/Calendar/full Drive).
  - **Microsoft 365** — PKCE + loopback is the recommended flow. Device flow works but Microsoft itself tells tenant admins to block it as a phishing vector — never make it primary.
  - **Slack** — newly feasible: PKCE for public clients went GA March 2026 (loopback and custom-scheme redirects, no secret) — but **user tokens only**; bot scopes still require a confidential app with a backend.
  - **Salesforce** — PKCE + loopback on an **External Client App** with "require secret" deselected; Salesforce's own Data Loader and `sf org login web` are the exact blueprint. Device flow also available on ECAs.
  - **Atlassian, HubSpot, Notion** — their raw OAuth **requires a client secret and has no PKCE** → a distributed native app cannot do it without a secret-holding proxy service. **But all three run official remote MCP servers whose auth *is* a public-client browser flow** (OAuth 2.1 + dynamic client registration). Since this ecosystem's harnesses consume MCP anyway, the MCP endpoint — not the raw API — is the correct integration surface for these three.

**Not feasible / must not be promised:**

- Fully in-app sign-in with no browser round-trip. Doesn't exist anywhere as a supported pattern.
- "Connect Atlassian/HubSpot/Notion" as a direct native OAuth against their APIs, without either a hosted proxy service or their MCP servers. (We choose MCP.)
- "It just works" in managed orgs. **The real ship-blockers are policy, not protocol**: Google restricted-scope verification + annual CASA assessment for Gmail/Drive; Microsoft publisher verification + tenant consent policies; Slack admin-approved apps (on by default on Enterprise Grid); GitHub OAuth-app organization access restrictions (on by default for new orgs); Salesforce API Access Control in locked-down orgs. The wizard must treat "your admin has to approve this" as a normal, designed-for state, not an error.

**One architectural consequence:** even the loopback listener belongs in the **CLI**, not the app. `cc auth login <provider> --json` should own the whole dance — open browser / print device code, listen or poll, exchange, keychain write — and stream states the app renders. That keeps invariant #1 (parse, never compute) and the no-secret-on-DTO fitness test intact, and makes every provider's sign-in the *same* seam the M3 wizard already froze for GitHub.

---

## 2. Per-platform summary table

| Platform | Native-app flow (2026) | User experience | Admin pre-config needed | Official remote MCP |
|---|---|---|---|---|
| **GitHub** (required first) | **Device flow** (secret-free; enable per app). PKCE exists but secret still required at exchange → not usable secret-free. Loopback redirect supported but moot without a public-client mode. | App shows 8-char code + button → browser at `github.com/login/device` → user enters code → CLI polls → done | Org owners approve the OAuth app (access restrictions default ON for new orgs), or install the GitHub App org-wide. Grant must cover `read:org` for team-based entitlements. | **Yes, GA** — `api.githubcopilot.com/mcp/`, OAuth 2.1 + PKCE or PAT |
| **Google Workspace** (Gmail/Cal/Drive) | **PKCE + loopback** (`http://127.0.0.1:<port>`), the documented Desktop-app flow. Device flow unusable (scope allowlist excludes Gmail/Calendar/full Drive). Custom URI schemes no longer supported. | Click → browser at `accounts.google.com` → approve → auto-redirect to loopback → "you can close this tab" | Workspace admin must configure app access (Trusted/Limited/Blocked; Gmail+Drive are restricted services). Publicly distributed app needs OAuth verification + **annual CASA assessment** for restricted scopes; "Internal" apps bypass it but require a per-org OAuth client. Testing-status apps: 7-day refresh tokens, 100-user cap. | **Yes, preview (May 2026)** — per-product Workspace MCP servers (`gmailmcp/drivemcp/calendarmcp.googleapis.com`), OAuth on the connection, bring-your-own OAuth client |
| **Microsoft 365** (Outlook/Teams/SharePoint) | **PKCE + loopback** ("Mobile and desktop" platform, public client enabled; localhost port-agnostic matching). Device flow supported but Microsoft advises tenants to block it. No broker required on macOS (Company Portal broker optional; needed only for device-based Conditional Access). | Click → browser at `login.microsoftonline.com` (MFA/Conditional Access run there) → approve → loopback redirect → done | Tenant consent policy usually requires **admin consent** (default policies restrict user consent to verified publishers/low-impact scopes); multi-tenant distribution effectively requires **publisher verification**. Admin-consent workflow can route user requests. | **Partial** — official MCP servers exist (Learn docs; Entra directory reads at `mcp.svc.cloud.microsoft/enterprise`, preview) but **none yet for Outlook/Teams/SharePoint user content** |
| **Slack** | **PKCE + loopback or custom scheme** — GA 2026-03-30, public client, no secret. **User-token scopes only** (desktop redirects can't request bot scopes). No device flow. Classic flow needs HTTPS redirect + secret (backend). | Click → browser at Slack consent page → approve → loopback/custom-scheme redirect → done | Workspace "admin-approved apps" gate (default ON for Enterprise Grid): admin approves the app before members can install. PKCE apps get **forced token rotation**: 12 h access tokens, 30-day-expiry refresh tokens. | **Yes, GA 2026-02-17** — `mcp.slack.com/mcp`, OAuth user tokens + PKCE; app must be Marketplace-published or internal |
| **Atlassian** (Jira/Confluence) | **No secret-free native flow.** 3LO = confidential-client only (secret required, no PKCE — ECO-283 still open, no device flow). Loopback can receive the code but exchange needs the secret. | Via the **Rovo MCP path**: click → browser OAuth 2.1 consent on Atlassian Identity → done (MCP client auto-registers via DCR). Raw 3LO would require our hosted proxy — rejected. | Admin controls on 3LO end-user installs + Data Security Policy app-access rules can require site-admin authorization; MCP has connected-app grant/revoke + IP allowlisting + audit log. | **Yes, GA** — `mcp.atlassian.com/v1/mcp/authv2`, OAuth 2.1 + dynamic client registration (public-client friendly); legacy `/v1/sse` dead after 2026-06-30 |
| **Salesforce** | **PKCE + loopback on an External Client App** ("require secret for web server flow" deselected → true public client; callback `http://localhost:<port>/OauthRedirect`). Device flow also available on ECAs (secret-free), gone from connected apps. Username-password grant retiring (enforced Winter '27) — never build on it. | Click → browser at the org's login → approve → loopback redirect → done (identical to `sf org login web`) | Default: users self-authorize with a consent screen. Admin options: "admin-approved users are pre-authorized" (profile/perm-set gated), refresh-token expiry policies, and **API Access Control** orgs block any non-allowlisted app → admin must install/allowlist first. | **Yes, GA** — Salesforce Hosted MCP Servers (SObject CRUD honoring FLS/sharing, Apex/Flow tools); auth = per-user OAuth + PKCE bound to an ECA; admin must enable servers in Setup |
| **HubSpot** (brief) | No PKCE, secret required → no native public client against the raw API. | Use official MCP instead. | Installer needs Super Admin / App Marketplace permission; MCP gated by admin-authorized app. | **Yes** — `mcp.hubspot.com` (CRM read/write), OAuth-based, moving to OAuth 2.1 + PKCE |
| **Notion** (brief) | No PKCE/device flow, secret required (Basic-auth token exchange) → no native public client against the raw API. | Use official MCP instead. | Per-user page-picker consent by default; Enterprise plan can allowlist approved connections. | **Yes** — `mcp.notion.com`, MCP auth spec with DCR (`token_endpoint_auth_method: none`) — secret-less public client outright |

---

## 3. Platform detail

### 3.1 GitHub — the mandatory first integration

GitHub gates the entire product: layer entitlements are GitHub-team-based, so no other integration matters until GitHub sign-in works.

**Flows.** GitHub supports the authorization-code grant and the OAuth 2.0 Device Authorization Grant for both OAuth Apps and GitHub Apps. Device flow must be enabled per app in its settings and **does not require the client secret** — the poll exchanges on `client_id` alone. PKCE (S256 only) was added in July 2025 and is recommended, **but GitHub does not distinguish public from confidential clients: the client secret is still required at every authorization-code token exchange**. Loopback redirects are supported (`127.0.0.1`/`::1` preferred over `localhost`; the redirect port need not match the registered callback port). Net: **device flow is the only secret-free native path**, which is exactly why `gh` CLI uses it — and it matches the device-flow seam already frozen in M3 (`cc auth --json`: initiate → `{user_code, verification_uri, expires_in, interval}`; poll → terminal state).

**UX.** App (via `cc`) requests codes → shows the `user_code` and an "Open github.com/login/device" button → user approves in the browser → CLI polls at the returned `interval` (respecting `slow_down`) → authorized.

**Tokens.** GitHub App user-access tokens: **8 hours**, refresh token **6 months**, rotation on use (expiration is opt-in, on by default for new apps; GitHub recommends keeping it). Classic OAuth-app tokens don't expire (revoked after 1 year unused).

**Admin pre-config.** For classic OAuth apps, **organization OAuth-app access restrictions are enabled by default on new orgs**: members cannot authorize an app for org resources until an org owner approves it (members can file a request; owners get notified). For GitHub Apps, an org owner installs the app (repo admins can install repo-scoped apps without org permissions). Whichever shape the copilot ecosystem app takes, the admin standup must include "approve/install the app for the org" — and the authorization must carry `read:org` (or the GitHub-App equivalent) so team-membership entitlement checks work.

**MCP.** Official remote GitHub MCP server, **GA since September 2025**, at `https://api.githubcopilot.com/mcp/`; supports OAuth 2.1 + PKCE (host apps register a GitHub/OAuth App) or PAT Bearer headers; per-toolset endpoints and OAuth scope filtering added January 2026.

Sources:
- https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps (device flow, loopback, PKCE params, secret required at exchange)
- https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/ (PKCE added; no public-client distinction — secret still required)
- https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens (8 h / 6 mo)
- https://docs.github.com/en/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions (org approval, default on)
- https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/limiting-oauth-app-and-github-app-access-requests-and-installations
- https://github.blog/changelog/2025-09-04-remote-github-mcp-server-is-now-generally-available/ · https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp-in-your-ide/set-up-the-github-mcp-server

### 3.2 Google Workspace (Gmail / Calendar / Drive)

**Flows.** For a "Desktop app" OAuth client, **authorization-code + PKCE with a loopback redirect (`http://127.0.0.1:<ephemeral-port>`) is the recommended and still-current flow** — the 2022 loopback deprecation hit only Android/iOS/Chrome-app client types, and OOB copy/paste died in 2023. Custom URI schemes are marked "no longer supported" for this use (app-impersonation risk). **Device flow exists but is useless here**: it is restricted to an allowlist of scopes (`email`, `openid`, `profile`, `drive.appdata`, `drive.file`, YouTube) — **no Gmail, no Calendar, no full Drive** — and installed-app/device clients get no incremental authorization.

**UX.** Click → CLI opens system browser at `accounts.google.com` with a one-shot listener on a loopback port → user approves → browser redirects to `127.0.0.1:<port>` → CLI exchanges code + verifier → browser tab shows "you can close this." No polling, no typing.

**Tokens.** Access tokens ~1 h (honor `expires_in`). Refresh tokens: **7-day expiry while the OAuth consent screen is in "Testing" status**; max **100 refresh tokens per account per client** (oldest silently dies); revoked on 6 months unused, user revocation, password change when Gmail scopes are held, or **when a Workspace admin flips the service to "Restricted."**

**Admin pre-config.** Workspace admins control third-party API access per app (**Trusted / Limited / specific-data / Blocked**) and per service (Gmail, Drive, Calendar restricted/unrestricted); tenants can block all unconfigured apps with a user request-access flow. **Gmail and most Drive scopes are "restricted" scopes**: public distribution requires OAuth verification plus a **CASA security assessment re-done every 12 months**; unverified apps cap at 100 users behind a scare screen. Apps marked **"Internal"** to one org bypass public verification entirely — which suggests the right enterprise pattern: **each customer org creates its own OAuth Desktop client** (an admin-standup step, delivered via inherited org config) rather than the project shipping one global verified client.

**MCP.** At Cloud Next '26 Google announced Google-managed MCP servers including **Workspace servers for Gmail, Drive, Calendar, Chat, People** (preview, rolling out from May 2026): per-product remote endpoints (`https://gmailmcp.googleapis.com/mcp/v1` etc.), **OAuth on the MCP connection with a bring-your-own OAuth client** — same consent/verification rules as above, so MCP shifts the surface but not the admin work.

Sources:
- https://developers.google.com/identity/protocols/oauth2/native-app (Desktop flow, loopback, PKCE, custom-scheme removal)
- https://developers.google.com/identity/protocols/oauth2/limited-input-device (device-flow scope allowlist)
- https://developers.google.com/identity/protocols/oauth2 (refresh-token expiry rules, 100-token cap)
- https://support.google.com/a/answer/7281227 (admin app access control) · https://support.google.com/cloud/answer/13463073 + https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification (restricted scopes, CASA, internal bypass) · https://support.google.com/cloud/answer/7454865 (unverified 100-user cap)
- https://cloud.google.com/blog/products/ai-machine-learning/google-managed-mcp-servers-are-available-for-everyone · https://developers.google.com/workspace/guides/configure-mcp-servers

### 3.3 Microsoft 365 / Entra ID (Outlook / Teams / SharePoint via Graph)

**Flows.** Register redirects under the **"Mobile and desktop applications"** platform with public-client flows enabled. **Auth-code + PKCE with loopback is the recommended desktop flow**; localhost redirect matching is **port-agnostic** (register `http://localhost/<app>` once, bind any ephemeral port; Microsoft prefers `127.0.0.1`, though the literal must be added via manifest; `[::1]` unsupported). Custom schemes (`msauth.<bundle-id>://auth`) exist for broker use. **Device flow is fully supported with no scope restrictions — but Microsoft's own Conditional Access docs call it "a high-risk authentication method" and recommend admins block it wherever possible**; expect enterprise tenants to have done so. No broker is required on macOS (unlike Windows WAM guidance): MSAL public clients default to the system browser; the Company Portal broker / Enterprise SSO plug-in matters only when tenants enforce device-based Conditional Access — on unenrolled Macs such tenants will fail any flow, which is a policy conversation, not an app defect.

**UX.** Click → browser at `login.microsoftonline.com` (MFA and Conditional Access run there, which is exactly why link-out is right) → approve → loopback redirect → done. Device flow as visible fallback only where tenants allow it.

**Tokens.** Access tokens 60–90 min by default. Refresh tokens: **90-day inactivity window for desktop apps, rotate on use, "until-revoked" max age — and their lifetimes have been non-configurable since 2021**; tenants force re-auth cadence via Conditional Access **sign-in frequency** instead. Admin password-reset/revocation kills public-client refresh tokens.

**Admin pre-config.** Most managed tenants restrict user consent (recommended `microsoft-user-default-low` policy: verified publishers + admin-classified low-impact permissions only) — so plan on **tenant admin consent** for Graph scopes like `Mail.Read`, `Calendars.Read`, `Sites.Read.All`. The opt-in **admin consent workflow** lets a blocked user's request route to reviewers. Multi-tenant distribution effectively requires **publisher verification** (verified Microsoft partner account; unverified new multi-tenant apps can't receive user consent beyond basic sign-in).

**MCP.** Official servers exist — Microsoft Learn MCP (docs, no auth), **Microsoft MCP Server for Enterprise** (`https://mcp.svc.cloud.microsoft/enterprise`, public preview — read-only **Entra directory** data with delegated OAuth) and Azure MCP — but **nothing first-party yet for Outlook/Teams/SharePoint user content**; Microsoft is steering that at M365 Copilot connectors. For mail/calendar/files, direct Graph with our own client remains the path.

Sources:
- https://learn.microsoft.com/en-us/entra/identity-platform/reply-url (loopback rules, port-agnostic localhost)
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code (device flow)
- https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-authentication-flows ("Microsoft recommends blocking device code flow wherever possible")
- https://learn.microsoft.com/en-us/entra/msal/python/advanced/macos-broker · https://learn.microsoft.com/en-us/entra/identity-platform/apple-sso-plugin (broker optional on macOS)
- https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens · https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes
- https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent · https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow · https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview
- https://learn.microsoft.com/en-us/graph/mcp-server/overview · https://learn.microsoft.com/en-us/training/support/mcp

### 3.4 Slack

**Flows.** The historical answer ("Slack OAuth needs a backend") is **obsolete as of 2026-03-30**: **PKCE for public clients is GA**. Enable in app settings or manifest (`"pkce_enabled": true` — a **one-way** switch marking the app a public client). PKCE apps may use **custom URI schemes or `http://localhost` loopback** redirects; token exchange uses `code + code_verifier`, refresh uses `refresh_token + client_id` — **no secret anywhere**. Two hard limits: **desktop redirects cannot request bot scopes (user-token scopes only)**, and there is **no device flow**. The classic confidential flow (HTTPS redirect + secret) still exists for bot-token apps and requires a backend.

**UX.** Click → browser at Slack's consent page → approve → loopback/custom-scheme redirect → CLI exchanges directly. No proxy.

**Tokens.** PKCE apps get **forced token rotation**: access tokens expire in **12 hours**; refresh tokens are single-use and — PKCE-specific — **expire after 30 days**, so an idle month means re-auth. (Classic non-rotating apps have non-expiring tokens; rotation, once on, can't be turned off.)

**Admin pre-config.** Workspace setting "only allow pre-approved apps"; **on Enterprise Grid, Admin Approval of Apps is on by default** — an org admin must approve the app (per workspace or org-wide) before members can authorize it. The **Slack MCP server additionally requires the app to be Marketplace(directory)-published or org-internal** — unlisted apps are prohibited from MCP.

**MCP.** Official Slack MCP server **GA 2026-02-17** at `https://mcp.slack.com/mcp` (search, messages, canvases, user info; scope-gated per tool). Auth = OAuth user tokens (`/oauth/v2_user/authorize`) with **PKCE available for desktop MCP clients**; admins govern it through the same app-approval queue. A separate Slackbot MCP *client* (June 2026) is the reverse direction.

Sources:
- https://docs.slack.dev/changelog/2026/03/30/pkce/ · https://docs.slack.dev/authentication/using-pkce/ (PKCE GA, public client, desktop redirects, no bot scopes, 30-day refresh)
- https://docs.slack.dev/authentication/installing-with-oauth/ (classic flow: HTTPS redirect + secret) · https://docs.slack.dev/authentication/using-token-rotation/ (12 h / single-use refresh)
- https://slack.com/help/articles/222386767-Manage-app-approval-for-your-workspace · https://slack.com/help/articles/360000281563-Manage-apps-in-an-Enterprise-organization
- https://docs.slack.dev/ai/slack-mcp-server/ · https://docs.slack.dev/changelog/2026/02/17/slack-mcp/

### 3.5 Atlassian (Jira / Confluence Cloud)

**Flows.** OAuth 2.0 (3LO) supports the **authorization-code grant only**: **no device flow, no PKCE** (feature request ECO-283 still "Gathering Interest," June 2026), and **`client_secret` is required at token exchange** — 3LO is confidential-client only. A localhost redirect can *receive* the code, but the exchange still needs the secret, so a distributed native app cannot do raw 3LO without a secret-holding proxy service. 2026 changes (resource-restricted tokens, multi-admin app ownership, tightened security requirements) did not add a public-client mode.

**Decision this forces.** We will not ship a hosted token-exchange proxy (a server holding an org's Atlassian secret contradicts "the app holds no secrets" in spirit and adds an internet-facing service to the trust boundary). **The vendor-supported no-secret native path is Atlassian's official Rovo MCP server**: OAuth 2.1 with **dynamic client registration** (RFC 7591/8414/9728) at `https://mcp.atlassian.com/v1/mcp/authv2` — a standards-compliant MCP client auto-registers as a public client and runs a normal browser consent. Since the harnesses consume MCP, Jira/Confluence integration = "connect the Atlassian MCP server."

**Tokens (for reference).** 3LO access tokens are short-lived (`expires_in`; ~1 h observed, not officially stated); refresh tokens need `offline_access`, **rotate on every use, 90-day inactivity expiry** (each rotation resets it), ~10-min reuse leeway, with a historically documented 1-year absolute cap (verify before hard-coding).

**Admin pre-config.** Historically pure user-consent, but no longer reliably: admin.atlassian.com can restrict end-user 3LO installs ("your site admin must authorize this app"), and **Data Security Policy app-access rules** can wall off projects/spaces from third-party apps. The MCP server has its own admin surface: connected-app grant/revoke, allowed AI-tool domains, IP allowlisting, audit logs.

Sources:
- https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/ (code grant only) · https://developer.atlassian.com/cloud/oauth/getting-started/implementing-oauth-3lo/ (secret required) · https://jira.atlassian.com/browse/ECO-283 (no PKCE)
- https://developer.atlassian.com/cloud/oauth/getting-started/refresh-tokens/ (rotating refresh, 90-day inactivity) · https://developer.atlassian.com/cloud/oauth/changelog/
- https://support.atlassian.com/atlassian-cloud/kb/your-site-admin-must-authorize-this-app-error-in-atlassian-cloud-apps/ · https://support.atlassian.com/security-and-access-policies/docs/manage-your-users-third-party-apps/
- https://www.atlassian.com/platform/remote-mcp-server · https://support.atlassian.com/atlassian-rovo-mcp-server/docs/configuring-oauth-2-1/ · https://github.com/atlassian/atlassian-mcp-server

### 3.6 Salesforce

**Flows.** Build on an **External Client App (ECA)** — the successor to connected apps; all new capabilities (device-flow config, hosted-MCP auth) land only on ECAs. The canonical native pattern is Salesforce's own: **auth-code + PKCE, "Require secret for Web Server Flow" deselected (true public client), callback `http://localhost:<port>/OauthRedirect`** — exactly what Data Loader's ECA guide instructs and what `sf org login web` does (default port 1717). PKCE is an opt-in checkbox on the app; custom URI schemes are also allowed. **Device flow is available on ECAs, secret-free** (10-minute codes, polling interval) — but note Salesforce disabled device flow on its own CLI/Data Loader connected apps in 2025 and permanently disabled the toggle for legacy connected apps. **Never build on the username-password grant** (blocked by default since Summer '23 orgs; retirement enforced Winter '27; SOAP `login()` dies June 2027). The May 2026 AppExchange mandate hardens OAuth settings (PKCE for public clients) — aligned with this design.

**UX.** Click → browser at the org's login URL (org-specific domain — the wizard must ask for or inherit the My Domain) → approve → loopback redirect → done. Device flow as headless fallback.

**Tokens.** Access-token lifetime = the org's **session timeout** (app Session Policies → profile → org settings). Refresh-token policy is **admin-chosen**: valid until revoked (default) / expire immediately / expire if unused for *n* / expire after *n*, plus an org-wide idle-TTL limiter and optional rotation — so the client must treat refresh-token death as a normal re-auth event, not an error.

**Admin pre-config.** Default **"All users may self-authorize"** (consent screen). Admins can flip to **"Admin-approved users are pre-authorized"** (profile/permission-set gated; those users skip consent). Orgs with **API Access Control** block every non-allowlisted app: there, an admin must install and allowlist the ECA before any user can OAuth — the wizard needs an "ask your admin" path.

**MCP.** **Salesforce Hosted MCP Servers are GA (2026)**: remote, Salesforce-hosted, SObject CRUD honoring field-level security and sharing, plus custom tools (Apex invocables, Flows, Named Queries, Data 360, Tableau). Auth is **per-user OAuth + PKCE bound to an ECA** ("You can't use Connected Apps for MCP authentication"); servers are inactive until an admin enables them in Setup → MCP Servers. The separate DX MCP server is local developer tooling.

Sources:
- https://developer.salesforce.com/docs/atlas.en-us.dataLoader.meta/dataLoader/loader_eca_oauth_pkce.htm (the public-client ECA blueprint)
- https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_connected_app.htm · https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_web_flow.htm (`sf org login web` pattern)
- https://help.salesforce.com/s/articleView?id=xcloud.remoteaccess_oauth_device_flow.htm · https://help.salesforce.com/s/articleView?id=xcloud.configure_device_flow_external_client_apps.htm (ECA device flow) · https://help.salesforce.com/s/articleView?id=005135030&type=1 (device flow blocked on standard CLI app)
- https://help.salesforce.com/s/articleView?id=xcloud.connected_app_manage_oauth.htm (refresh policies, permitted users) · https://help.salesforce.com/s/articleView?id=005228838&type=1 (API Access Control)
- https://help.salesforce.com/s/articleView?id=release-notes.rn_security_username_password_flow_retirement.htm&release=260 (password-grant retirement)
- https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/hosted-mcp-servers-overview.html · https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/client-connection-overview.html

### 3.7 HubSpot and Notion (brief)

**HubSpot.** Raw OAuth: authorization-code only, **secret required, no PKCE** (long-open community request); HTTPS redirects in production (localhost HTTP for testing only) → no native public client. Installation requires Super Admin / App-Marketplace permission. **Official remote MCP server at `mcp.hubspot.com`** (CRM objects read/write, OAuth-based, moving to OAuth 2.1 + PKCE, gated by an admin-authorized app) — the MCP endpoint is the native-friendly surface.
Sources: https://developers.hubspot.com/docs/apps/legacy-apps/authentication/working-with-oauth · https://developers.hubspot.com/mcp

**Notion.** Raw OAuth: token exchange uses HTTP Basic `CLIENT_ID:CLIENT_SECRET`, **no PKCE or device flow** → no native public client. Default is per-user consent with a page-picker; Enterprise workspaces can allowlist approved connections. **Official hosted MCP at `mcp.notion.com` implements the MCP auth spec with dynamic client registration and `token_endpoint_auth_method: none`** — a secret-less public client, the cleanest MCP auth story of any vendor surveyed.
Sources: https://developers.notion.com/docs/authorization · https://developers.notion.com/guides/mcp/build-mcp-client · https://www.notion.com/help/enterprise-connection-settings

---

## 4. Recommended pattern for Control Tower

Constraints honored: the app never embeds provider auth UI; the app holds no secrets (all tokens written to the macOS keychain by the `cc` CLI); sign-in is always a link-out to the provider's real page; GitHub is mandatory and first.

### 4.1 The one seam, three variants

Everything goes through **`cc auth login <provider> --json`** (the M3 frozen seam, generalized). The CLI owns: browser launch, the loopback listener *or* device-code polling *or* the MCP OAuth 2.1 client, the token exchange, and the keychain write. The app only renders the CLI's streamed states. No token, code verifier, or secret ever appears on an app DTO (existing fitness test: no-secret-on-DTO).

| Variant | Providers | Why |
|---|---|---|
| **A. Device flow** | **GitHub** (primary and only secret-free GitHub option) | Matches the frozen M3 seam and `gh` precedent; no listener, survives SSH/kiosk contexts |
| **B. PKCE + loopback** (`127.0.0.1:<ephemeral>` listener owned by the CLI, one-shot) | **Google Workspace** (device flow can't reach Gmail/Calendar/Drive scopes) · **Microsoft 365** (device flow tenant-blocked per Microsoft's own advice) · **Slack** (user-token PKCE app) · **Salesforce** (public-client ECA, `sf`-CLI pattern; device flow on the same ECA as headless fallback) | The vendor-recommended desktop flow on all four; one click, no code typing |
| **C. Remote MCP connect** (OAuth 2.1 + DCR performed by the MCP client config the CLI materializes) | **Atlassian** (raw 3LO is confidential-only — MCP is the sole no-secret path) · **HubSpot** · **Notion** | Their raw APIs require a client secret; their official MCP servers are public-client by design, and the ecosystem's harnesses consume MCP anyway |

Rule of thumb the doc establishes: **integrate at the surface where the vendor made native public-client auth first-class.** For GitHub/Google/Microsoft/Slack/Salesforce that's their OAuth endpoint; for Atlassian/HubSpot/Notion it's their MCP server.

### 4.2 What the app renders during the wait

- **Variant A (GitHub):** the `user_code` in large type, an "Open GitHub" button (`verification_uri`), a countdown from `expires_in`, and a phase-named status ("Waiting for you to approve in the browser…"). No ETA bars (Case Law OUT); progress is by phase name. Terminal states: authorized / denied / expired / timeout, each with a retry.
- **Variant B:** a "Continue in your browser" card the moment the browser opens — "We've opened <provider>'s sign-in page. Approve access there; this window will update by itself." Plus an always-visible "Browser didn't open?" link that re-triggers the URL (copyable). Terminal states: signed in / denied / timed out (listener closes after `expires_in`).
- **Variant C:** identical to B from the user's perspective (browser consent), labeled honestly: "Connecting to <provider>'s MCP server."
- **Blocked-by-admin is a designed state, not an error:** every provider card needs a third resting state — "Waiting for your admin to approve <app> for <org>" — with provider-specific copy (see 4.3) and, where the provider has one, the request-access action (GitHub org approval request; Microsoft admin-consent workflow; Slack approval queue; Google request-access flow).

### 4.3 What an org admin must pre-configure (feeds the Admin standup / inherited org config)

| Platform | Admin pre-config |
|---|---|
| **GitHub** | Approve the OAuth app for the org (access restrictions default ON) or install the GitHub App org-wide; ensure the grant covers `read:org` for team-entitlement checks. This belongs in the existing admin standup ("Connect GitHub" is already the true pre-run gate). |
| **Google Workspace** | Recommended enterprise pattern: the org creates its **own "Internal" Desktop OAuth client** (bypasses public verification + CASA) and distributes its client ID via inherited org config (a client ID is not a secret); admin sets the app to Trusted/Limited in API controls and leaves Gmail/Drive restricted-service policy compatible. Publishing one global client instead means owner-level work: OAuth verification + annual CASA. |
| **Microsoft 365** | Tenant admin grants **admin consent** to the app's delegated Graph scopes (or enables the admin-consent workflow); if we distribute multi-tenant, the publisher must complete **publisher verification**. Alternative mirror of the Google pattern: each tenant registers its own public-client app and inherits the client ID. Tenants enforcing device compliance need Intune-enrolled Macs — flag, don't fight. |
| **Slack** | Admin approves the app in "admin-approved apps" (org-wide on Enterprise Grid). If the Slack MCP server is used, the app must additionally be Marketplace-published or built as the org's internal app. |
| **Atlassian** | Admin permits the Atlassian MCP connection (connected-app grant in admin.atlassian.com), checks Data Security Policy app-access rules don't wall off needed projects/spaces, optionally sets IP allowlists. |
| **Salesforce** | Admin creates/installs the **External Client App** (PKCE on, web-server-secret off, localhost callback), sets Permitted Users + refresh-token policy; in API-Access-Control orgs, allowlists it. For Hosted MCP: enable the MCP server in Setup and bind it to the ECA. |
| **HubSpot / Notion** | HubSpot: admin authorizes the MCP-linked app (Super Admin). Notion: default needs no admin (user page-picker); Enterprise allowlist must include the connection. |

### 4.4 Token custody and renewal (CLI-side, stated for completeness)

- All tokens land in the **per-user macOS keychain** via `cc` (invariant #6; the secret-store distinction is untouched — these are the *user's own* integration tokens, not shared-store material).
- The CLI must treat refresh-token death as **normal**: Slack PKCE refresh tokens die after 30 idle days; Microsoft after 90 idle days; Atlassian MCP after 90 idle days; Google Testing-status after 7 days; Salesforce whenever the admin says so. `doctor.auth[]` (`{identity, scope, state}`) is already the frozen render contract for "needs sign-in" — these expirations are exactly what it should surface, and the tray can prompt re-auth as routine upkeep, never as a failure alarm.
- Prefer providers' expiring-token modes where optional (GitHub App user tokens with expiration ON) — short-lived tokens plus keychain custody is the strongest posture available without holding any secret.

---

## 5. Design implications for the wizard's Integrations step

What the screen can honestly show, given all of the above:

1. **No embedded webviews, ever — and say why with confidence.** The sign-in happens on the provider's real page, in the user's real browser, where their password manager, passkeys, MFA, and their company's Conditional Access all already work. Copy angle: "You'll sign in on GitHub's own page — we never see your password, and your company's security rules apply as normal." This is a trust feature to surface, not a limitation to apologize for.
2. **One card per integration, four honest states:**
   - **Not connected** → a single **"Connect…"** button (link-out). GitHub's card is first and marked required; the others are optional and can be deferred.
   - **Waiting** → variant-specific: GitHub shows the big `user_code` + "Open GitHub" + countdown; browser-flow providers show "Continue in your browser" + re-open link. Status advances by phase name only, no ETAs, and the window updates itself when the CLI reports the terminal state.
   - **Needs admin approval** → a calm, provider-specific explanation of who must do what ("Your GitHub org owner needs to approve this app — we've sent the request"), with the provider's request-access action wired where one exists. This state is *expected* in managed orgs and must not look like an error.
   - **Connected** → identity shown (rendered from `doctor.auth[]`: `{identity, scope, state}`), with a disconnect action (CLI revokes + keychain delete). Re-auth prompts (expired refresh tokens) return the card to Not connected with a one-line "session expired — reconnect" note, styled as routine.
3. **GitHub gates the step.** The wizard's Integrations step opens with GitHub via device flow (the already-frozen M3 seam) and does not present other integrations as actionable until GitHub is Connected — layer entitlements (GitHub teams) determine what else the user is even entitled to connect.
4. **The app never runs auth machinery.** No listener, no polling loop, no OAuth client in Swift: `cc auth login <provider> --json` streams `{state, user_code?, verification_uri?, expires_in?, identity?}` and the app renders it (parse-never-compute holds even here). The DTOs carry no token field — the existing no-secret-on-DTO fitness test extends to every provider.
5. **MCP-surface integrations are labeled as what they are.** Atlassian/HubSpot/Notion cards say "Connects via <vendor>'s official MCP server" — one line of education that matches the ecosystem's registry model (integrations are declared in layer repos; the harnesses consume MCP). Same button, same states; only the plumbing note differs.
6. **Admin dependencies surface in Admin mode, not just user-side.** The per-platform admin table (§4.3) feeds the admin standup's instructional content (the integrations screen is already education-first per the ratified admin redesign): an org that wants Google/Microsoft integrations to work on day one pre-creates the internal OAuth clients / grants admin consent / approves the Slack app as part of standup, and distributes the resulting client IDs via inherited org config — client IDs are not secrets and may travel in inheritance; tokens never do.
7. **What the wizard must never promise:** silent sign-in with no browser trip; bot-scope Slack behavior (user-token only on this path); Gmail/Drive access without the org's Workspace admin having acted; working device-flow on Microsoft tenants that block it. Where a tenant policy blocks a flow, the card explains the policy and who can change it — the icon can't lie during setup either.

---

*Research compiled 2026-07-16 from official vendor documentation (URLs inline per platform). Prior decisions honored: M3 wizard sign-in seam (`cc auth --json` device flow, app holds no secret), admin-redesign integration model (integrations live in layer repos; admin standup is infrastructure-only), invariant #1 (parse, never compute) and invariant #6 (secrets never travel in inheritance).*
