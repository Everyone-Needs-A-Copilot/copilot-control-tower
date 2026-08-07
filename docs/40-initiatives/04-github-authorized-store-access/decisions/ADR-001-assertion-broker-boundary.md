# ADR-001 — Organization-operated OIDC assertion broker

Status: Accepted

Date: 2026-08-07

Supersedes: the credential-minting portion of work product 586; preserves its
Python-first and acceptance-gate sequencing

## Context

The setup journey can reconcile repositories and Product projects, but the
publisher Mac's stored Infisical Universal Auth pair is rejected. Supplying a
new permanent pair would recover one Mac without completing self-service or
offboarding. ADR-009 ratified B-prime: translate live GitHub entitlement into a
short-lived OIDC assertion that pre-scoped Infisical identities trust.

The product SOUL also forbids turning Control Tower into a hosted service. That
does not forbid an organization from operating open-source infrastructure next
to its own Infisical instance; it forbids a closed or Control Tower-operated
central service becoming the product's trust path.

## Decision

Build the broker as a public, independently deployable Python service in the
Control Tower source repository. Each organization operates its own instance.

The broker:

- holds no Infisical credential;
- authenticates machines by SSH challenge-response;
- authorizes the reserved `everyone` scope by live access to the protected
  policy repository and team-specific scopes by live team membership;
- reads the protected `team_scopes` mapping with the same least-privilege App;
- signs short-lived, scope-bound OIDC assertions;
- publishes discovery/JWKS endpoints;
- rate-limits and records metadata-only decisions.

The existing end-user device-flow client and the broker's GitHub App are
separate trust anchors. A public `github_app.client_id` is not evidence that the
broker has an installed App or private key; production code requires each
explicitly. Every installation token is downscoped to the protected policy
repository and `Contents: read` plus `Metadata: read`. `Members: read` is an
additional requirement only for a configured team-specific scope.

Python in CLI Copilot owns assertion exchange and short-lived token caching.
`cc` owns setup orchestration, progress, verification, and person-facing JSON.
Swift owns display only.

## Consequences

- GitHub offboarding prevents the next assertion without an Infisical sweep;
  residual access is bounded by the 15-minute store token TTL.
- Interactive Macs no longer need Infisical client credentials in Keychain.
- Broker availability becomes a runtime dependency after the cached token
  expires, and must produce an honest unavailable state.
- Day-zero Infisical trust, GitHub App installation/designation, DNS custody,
  and platform-admin MFA remain explicit operator acts.
- Existing Universal Auth support remains for headless actors and a bounded
  migration window, but is not a fallback for a configured interactive broker.

## Rejected alternatives

- **Mint Universal Auth pairs per Mac.** Rejected because the broker would hold
  store-equivalent grant power, long-lived credentials would persist locally,
  and offboarding would require a second revocation system.
- **Use the existing public device-flow client ID as broker authorization.**
  Rejected because a client ID grants no App installation token and proves no
  repository or team authority.
- **Send the user's GitHub bearer token to the broker as the primary path.**
  Rejected as a bearer-token sink. It remains a documented design fallback but
  is not enabled in the production contract.
- **Put authorization logic in Swift.** Rejected by parse-never-compute and the
  packaged-helper contract boundary.
- **Let setup push when GitHub says the user can write.** Rejected because setup
  is a consumer/download path. Authoring requires a separate explicit action.
