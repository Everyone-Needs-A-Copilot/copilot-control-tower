# Phase 1 — Contract and threat model

Status: active

Execution: `tc` tasks 258-260

## Invariants served

1. Python remains the sole resolver, authorization client, writer, verifier,
   and diagnostic authority. Swift parses and renders only.
2. Setup is pull-only for shared ecosystem repositories. GitHub write authority
   is evidence for a separate authoring workflow, never setup permission.
3. Product work may receive one additive local checkpoint commit only when the
   complete tracked/untracked work and prior index can be preserved.
4. An interactive Mac receives no long-lived Infisical client ID or client
   secret. A short-lived access token may be cached only within Infisical's own
   900-second TTL.
5. A missing or malformed security field fails closed. There is no force,
   skip-verification, or lower-security mode.

## Components and trust boundaries

### Organization-operated assertion broker

- Runs as an independently deployable Python service from this public source
  tree; it is not embedded in or launched by the Mac app.
- Publishes OIDC discovery and JWKS endpoints.
- Issues RS256 assertions with exact issuer, audience, subject, organization,
  machine, and scope claims and a single-use `jti`.
- Holds only its signing key and a GitHub App private key. It has no Infisical
  credential and no ability to create identities or permissions.
- Checks organization/team membership live through the GitHub App installation
  token. `team_scopes` is read from the protected organization configuration.
- Verifies a single-use, at-most-60-second SSH challenge signed by the Mac's
  existing encrypted Copilot device key.
- Emits structured metadata-only audit events. It never logs the challenge
  signature, assertion, GitHub token, Infisical token, or secret value.

### Python client and credential ladder

- Reuses the already-provisioned `~/.ssh/id_ed25519_copilot` identity through
  `ssh-keygen -Y sign`; the private key stays encrypted and agent-backed.
- Requests a nonce, signs a canonical request, receives one assertion per
  entitled scope, and exchanges the selected assertion at Infisical's OIDC
  login endpoint.
- Caches only the returned short-lived access token, namespaced by organization,
  endpoint, identity, and scope, mode `0600`, with a 60-second expiry skew.
- Uses that token through the existing `InfisicalClient`; secret values remain
  process-local and are never returned by `cc connections` or diagnostics.
- Universal Auth remains supported only as an explicitly configured legacy or
  headless path during migration. A broker-configured interactive path never
  silently falls back to a rejected long-lived pair.

### Swift renderer

- Starts one packaged Python journey and renders versioned reports/progress.
- Does not perform GitHub membership checks, Infisical exchange, repository
  reconciliation, confidence calculation, or error classification.

## Protocol contracts

The broker exposes:

- `GET /.well-known/openid-configuration`
- `GET /.well-known/jwks.json`
- `POST /v1/challenges`
- `POST /v1/assertions`
- `GET /healthz`

`POST /v1/challenges` returns only a nonce identifier, nonce, and expiry.
`POST /v1/assertions` accepts the exact signed canonical request and returns
scope rows containing `scope`, `identity_id`, `assertion`, and assertion expiry.
The assertion value is consumed inside the credential ladder and is forbidden
from every `cc --json` schema and support report.

The inherited non-secret store configuration gains:

- `broker_url`
- `broker_issuer`
- `broker_audience`
- `team_scopes[].scope`
- `team_scopes[].identity_id`

Each scope row remains read-only, has no wildcards, and maps one GitHub team (or
the reserved `everyone` membership) to one Infisical environment/path and one
pre-created OIDC identity.

## Security fitness functions

- nonce TTL is at most 60 seconds and every nonce is consumed once;
- per-login rate is at most 10/minute and per-source-IP rate 30/minute;
- assertion `exp - iat` is at most 60 seconds;
- Infisical access-token TTL is exactly 900 seconds in live trust config;
- unknown team, malformed scope, missing App permission, stale configuration,
  bad SSH signature, wrong issuer/audience, or negative-scope success all fail;
- all denial responses are generic to unauthenticated callers and detailed only
  in metadata-safe operator logs;
- logs and diagnostics fail tests if a JWT, GitHub token, client secret, or
  secret value appears;
- GitHub removal prevents the next assertion and bounds existing access to the
  current Infisical token's remaining TTL.

## Deployment gates that code cannot impersonate

The following require authenticated owner/operator accounts and must be stored
as evidence, not assumed:

- hardware-backed MFA on every Infisical platform-admin account;
- a dedicated organization-controlled GitHub App with `Members: read` and only
  the repository-content access required to read protected `team_scopes`;
- DNS 2FA, DNSSEC, and registry/transfer lock where available;
- Coolify secret-manager custody for the broker signing/App keys;
- per-scope Infisical OIDC identities and a positive-plus-negative live proof;
- written Infisical guidance on JWKS caching or static-key pinning.
