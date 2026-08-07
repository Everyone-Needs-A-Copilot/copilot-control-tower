# Control Tower access broker

This is the open-source, organization-operated OIDC assertion service defined
by Control Tower's B-prime architecture. It verifies a Mac's SSH signature,
checks current access to the protected policy repository through a
least-privilege GitHub App token, and issues a short-lived scope assertion that a pre-created
Infisical machine identity can exchange for a 15-minute access token.

It deliberately has no Infisical credential and no identity-management API.

## Required secret files

- `BROKER_SIGNING_KEY_FILE`: RSA private key used only to sign OIDC assertions.
- `BROKER_GITHUB_PRIVATE_KEY_FILE`: private key for the organization-controlled
  GitHub App with read access to the policy repository. Team-specific scopes
  additionally require `Members: read`; an `everyone` scope does not.

Both paths must point to files mounted from the host secret manager. Raw key
material is not accepted through environment variables.

## Required non-secret configuration

```text
BROKER_ISSUER=https://access.example.org
BROKER_AUDIENCE=https://secrets.example.org
BROKER_ORG=Example-Org
BROKER_GITHUB_APP_ID=12345
BROKER_GITHUB_INSTALLATION_ID=67890
BROKER_POLICY_REPOSITORY=Example-Org/copilot-internal
BROKER_POLICY_PATH=ecosystem.yml
BROKER_POLICY_REF=main
BROKER_SIGNING_KEY_ID=2026-08
BROKER_DATABASE_PATH=/var/lib/control-tower-access-broker/events.sqlite3
BROKER_TRUSTED_PROXY_CIDRS=172.16.0.0/12
```

The policy repository's `store.team_scopes` rows must include `team`, `scope`,
`environment`, `secret_path`, `access: read`, and the pre-created Infisical
`identity_id`. Wildcards, write access, relative paths, and unknown fields fail
closed.

The container disables request access logs so request bodies can never be
captured accidentally. The service emits its own allowlisted JSON audit events;
they contain decisions and correlation metadata only, never an SSH signature,
OIDC assertion, GitHub token, Infisical token, or secret value.

## Deployment posture

`compose.example.yml` demonstrates the required runtime boundary: non-root,
read-only filesystem, every Linux capability dropped, no privilege escalation,
a bounded no-exec temporary filesystem, durable count-only circuit-breaker
state, and file-mounted secrets. Put TLS at the organization's reverse proxy;
publish only that HTTPS origin. Replace every example non-secret environment
value with the organization-specific values listed above.

The GitHub App must have read access to the protected policy repository. The
broker downscopes every installation token to that one repository and only
`Contents: read` plus `Metadata: read`, even if the registered App has broader
permissions. Team-specific scopes require organization `Members: read`; the
reserved `everyone` scope is granted by current access to the policy repository
itself. The per-scope Infisical OIDC identities must have read access only to
their declared environment/path. The broker has no Infisical token, client ID,
or client secret.
