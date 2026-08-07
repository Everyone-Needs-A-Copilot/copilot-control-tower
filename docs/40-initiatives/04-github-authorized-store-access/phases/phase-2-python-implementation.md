# Phase 2 — Python implementation

Status: implemented locally; full regression and live deployment gates remain

Execution: `tc` tasks 259, 260, and 262

## Delivered surfaces

### Organization-operated broker

`services/access-broker/` now provides the open-source FastAPI broker:

- strict environment and private-file validation;
- OIDC discovery and JWKS publication;
- single-use, 60-second SSH challenges;
- GitHub App organization/team authorization;
- protected `team_scopes` parsing with explicit read-only paths and no
  wildcards;
- RS256 scope assertions lasting at most 60 seconds;
- per-login and per-IP rate limits plus a count-only issuance circuit breaker;
- allowlisted metadata-only audit events;
- a pinned, non-root container and hardened Compose example; and
- regression coverage for signing, replay, entitlement, policy widening,
  validation redaction, rate limiting, circuit breaking, and GitHub evidence.

The broker contains no Infisical credential or identity-management operation.

The OIDC exchange was checked against the exact Infisical version running in
ENAC (`v0.154.6`). Its login contract accepts only `identityId` and `jwt` for
this use; the client sends that exact body to
`POST /api/v1/auth/oidc-auth/login`.

### CLI Copilot

The Python credential layer now:

- reads the non-secret GitHub identity pointer written by `cc auth`;
- derives a stable machine identifier from the existing Copilot public key;
- signs the broker challenge through the SSH agent;
- exchanges the selected scope assertion at Infisical's OIDC login endpoint;
- rejects issuer, audience, organization, scope, machine, expiry, and response
  mismatches;
- caches only the short-lived access token in a mode-0600 file within its own
  expiry;
- retries once after a stale token;
- never falls back to Universal Auth when a broker is configured; and
- creates a read-only `InfisicalClient` that rejects every mutating HTTP method
  before network I/O.

`copilot infisical --json access verify` performs the operational positive and
negative proof without returning secret names or values.

### `cc`

- `cc store verify --json` validates protected organization policy and invokes
  the CLI's positive-read/negative-denial proof.
- `cc reconcile run --json` now requires that store phase before it may return
  `operational: true` and `confidence: 0.95`.
- `cc support latest --json` returns the newest private, redacted setup report
  in a paste-ready envelope. The report is accepted only when it is a regular,
  current-user-owned, mode-0600 file with the expected schema and kind.

## Setup write authority

Setup remains a consumer workflow:

- eligible dirty Product work receives a local checkpoint commit;
- Foundation, Internal, and Department repositories are downloaded and
  fast-forwarded only when their histories prove that safe;
- setup performs zero pushes even if GitHub says the current account can
  author that repository; and
- GitHub write/maintain/admin authority is retained only as evidence for a
  separate, explicit authoring workflow.

This is intentional. A person's permission to publish shared ecosystem source
does not convert an unattended setup run into a publishing action.

## Remaining acceptance evidence

Phase 2 is not a production-ready claim until:

- CLI Copilot and `cc` releases containing these changes are published and
  selected by the hierarchy;
- the ENAC broker is deployed from immutable source;
- the separate least-privilege GitHub App exists and is installed;
- Infisical identities and OIDC trust are configured with 900-second tokens;
- the protected ENAC policy and CLI overlay select the broker path;
- the old interactive Universal Auth pair is removed after the audit window;
- live positive and negative store proofs pass; and
- `cc reconcile run --json` returns the 0.95 operational verdict on the
  publisher Mac.
