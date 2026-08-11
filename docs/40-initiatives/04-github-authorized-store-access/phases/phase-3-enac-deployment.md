# Phase 3 — ENAC deployment and live proof

Status: blocked on authenticated owner/operator control-plane actions

Execution: `tc` task 261

This phase is deliberately explicit. Local code cannot impersonate an
organization owner, create an Infisical trust relationship without an
authenticated admin session, or claim a DNS/TLS deployment exists.

## 1. Publish immutable Python source

1. Merge and tag the CLI Copilot release containing broker authentication.
2. Merge and tag the `cc` release containing `store verify`, `support latest`,
   and the store-gated setup journey.
3. Push the Control Tower commit containing `services/access-broker/`.
4. Record all three immutable commit IDs in the deployment evidence.

## 2. Create the broker GitHub App

Create a dedicated organization-owned App. It is not the end-user OAuth App.

- Organization permissions: Members, read-only.
- Repository permissions: Contents, read-only.
- Repository selection: only the protected organization-policy repository.
- Webhooks: not required by the current live-check implementation.
- Installation: the ENAC organization only.

Store the App ID and installation ID as non-secrets. Mount the generated App
private key into the broker as a mode-0400 file owned by uid 10001. Do not put
the key in Git, an environment-variable value, an image layer, or an
interactive Mac's Keychain.

## 3. Create and deploy the broker signing key

Generate a dedicated RSA key of at least 2048 bits in the deployment secret
manager. Mount it as a mode-0400 file owned by uid 10001. Publish only the
broker's HTTPS origin; terminate TLS at the organization's reverse proxy.

Deploy using the Dockerfile and the security posture demonstrated in
`services/access-broker/compose.example.yml`: non-root, read-only root
filesystem, all Linux capabilities dropped, no privilege escalation, bounded
no-exec temporary storage, and durable count-only state.

Verify `/healthz`, OIDC discovery, and JWKS from outside the deployment host.

## 4. Configure Infisical

For each protected scope, create one machine identity and attach OIDC Auth:

- discovery URL and bound issuer: the exact broker HTTPS origin;
- bound audience: `https://secrets.ineedacopilot.com`;
- bound claims: exact organization and exact `copilot_scope` for that identity;
- access-token TTL: 900 seconds;
- project/environment/path: the exact row declared by `team_scopes`;
- permission: read only.

Create the shared identity first. Create department identities only for live
department scopes. Record identity IDs; they are non-secret policy references.

## 5. Publish protected inherited policy

Update `claude-copilot-internal/ecosystem.yml` with:

```yaml
store:
  status: connected
  type: infisical
  endpoint: https://secrets.ineedacopilot.com
  workspace_id: "458e8f7a-3d53-4e72-9d1c-718956463e2f"
  environment: prod
  secret_path: /shared
  broker_url: https://<enac-broker-host>
  broker_issuer: https://<enac-broker-host>
  broker_audience: https://secrets.ineedacopilot.com
  team_scopes:
    - team: everyone
      scope: shared
      environment: prod
      secret_path: /shared
      access: read
      identity_id: <shared-oidc-identity-id>
```

The existing protected-branch rule must remain enforced for administrators.
The change goes through review; it is not pushed by setup.

Update the organization CLI overlay with the equivalent non-secret
`infisical_broker_*` and `infisical_store_scope` fields. Remove the interactive
Universal Auth `requires_secret` pair only after the broker path is live.

## 6. Prove and cut over

On the publisher Mac, using the same GitHub account and device key path as a
normal user:

```bash
copilot infisical --json access verify \
  --project 458e8f7a-3d53-4e72-9d1c-718956463e2f \
  --env prod \
  --path /shared \
  --negative-path /__control_tower_denied__ \
  --scope shared

cc store verify --json
cc reconcile run --json
cc support latest --json
```

Acceptance requires `positive_read: true`, `negative_denied: true`,
`read_only: true`, and the final setup report's `operational: true` with
`confidence: 0.95`.

After the ratified clean-audit interval shows no use of the old interactive
Universal Auth identity, revoke its client secret, delete the identity if it
has no headless consumer, and remove its Keychain entries from interactive
Macs.
