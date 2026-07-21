# Ground-up Claude and Codex installation

This is the Phase 6 operator path for an ENAC installation with no department
layer. It separates commands that work today from the onboarding transaction
Phase 6 still has to implement. Do not replace a missing automated step with
hand-written layer YAML and then call the machine onboarded.

## Required result

Both products must resolve the same roles without sharing namespaces:

| Product | Rank 10 | Rank 30 | Rank 40 |
|---|---|---|---|
| Claude | user-owned `claude-copilot-private` | ENAC `claude-copilot-internal` | public `claude-copilot` |
| Codex | user-owned `codex-copilot-private` | ENAC `codex-copilot-internal` | public `codex-copilot` |

Admin Setup creates/verifies rank 30 and the rank-40 references. User Setup,
authenticated as the individual, creates/selects rank 10. `cc` resolves and
materializes; Control Tower renders the result.

## 1. Owner prerequisites

Before the real Admin run, an organization owner must:

1. create the ENAC GitHub OAuth App in the GitHub web UI, enable device flow,
   and retain its public client id (never use or distribute its client secret);
2. make the Apple Developer ID/notary credentials available to the release
   pipeline without putting them in git or a brief;
3. authorize scoped, revocable per-machine Infisical identities;
4. confirm the operator's `gh` token has `repo` and `admin:org` scopes.

These are explicit owner gates. Automation must report them missing; it may not
invent identifiers or weaken credential policy.

## 2. Install the public foundations (works today)

Install Claude Copilot and its `cc` control-plane CLI:

```bash
mkdir -p "$HOME/.claude"
git clone https://github.com/Everyone-Needs-A-Copilot/claude-copilot.git "$HOME/.claude/copilot"
bash "$HOME/.claude/copilot/tools/cc/install.sh"
"$HOME/.local/bin/cc" --version
```

Install the released Codex Copilot plugin from a local checkout of the public
tag:

```bash
mkdir -p "$HOME/.local/share/enac"
git clone --branch v0.6.0 https://github.com/Everyone-Needs-A-Copilot/codex-copilot.git "$HOME/.local/share/enac/codex-copilot"
codex plugin marketplace add "$HOME/.local/share/enac/codex-copilot"
codex plugin add codex-copilot@codex-copilot-local
codex plugin list
```

This establishes only the public foundations. It does not establish the
organization or personal layers.

> The `cc` executable name shadows the system C compiler. Source builds must set
> `CC=/usr/bin/clang` and `CXX=/usr/bin/clang++` where the build tool consults
> those variables; never assume bare `cc` means a compiler.

## 3. Build and verify Control Tower from source (works today)

From the Control Tower checkout:

```bash
bash scripts/tests/test_admin_bootstrap.sh
bash scripts/build-admin.command --build-only
bash scripts/build-user.command --build-only
```

These commands prove the development builds. Distribution still requires the
signed/notarized pipeline and its owner-controlled credentials.

## 4. Run Admin Setup (Phase 6 execution)

The Admin brief must declare:

```yaml
org: Everyone-Needs-A-Copilot
harness: [claude, codex]
departments: []
```

It also carries the connected store pointer, team-scope mapping, public GitHub
OAuth client id, and contacts. It carries no secret and no personal repository.
Admin Setup must then:

1. verify public Claude/Codex foundation pins, including Codex `v0.6.0`;
2. create or verify `knowledge-copilot-internal`, `cli-copilot-internal`,
   `claude-copilot-internal`, and `codex-copilot-internal` as private repos;
3. configure branch protection and base-read policy;
4. author `ecosystem.yml`, including the user-owned personal handoff contract;
5. pass the fail-closed leak scan;
6. return `must_fix: 0`, including `github-app`, `foundation-pin`, and
   `personal-handoff` checks.

The existing engine supports the shared-repository work, but Phase 6 must add the
personal-handoff and complete GitHub-app verification before this section is
accepted end to end.

## 5. Run User Setup (Phase 6 target; command not implemented yet)

The intended single transaction is:

```bash
cc onboard --org Everyone-Needs-A-Copilot --products claude,codex --json
```

It must:

1. authenticate the individual through the organization's device-flow client;
2. create or select the user's private Claude and Codex personal repositories;
3. generate independent on-device SSH credentials and register only public keys;
4. provision a scoped per-machine store identity into the OS keychain;
5. resolve winners by `(product, dimension, item)`;
6. materialize only to product-specific allowlisted targets;
7. coordinate CLI mirror sync and run doctor;
8. return opaque personal provenance and the three-layer result for each product.

Until this verb exists, the machine is not a valid ground-up onboarding proof.
Do not hand-place a unified manifest or reuse an administrator credential to make
the status appear green.

## 6. Acceptance evidence

Capture all of the following on both the Admin machine and a clean User machine:

- `cc onboard ... --json` reports `personal (10) -> organization (30) ->
  foundation (40)` for Claude and Codex;
- same-named Claude and Codex skills coexist with product-correct provenance;
- `cc doctor --json` is healthy with a valid unified manifest;
- CLI mirrors are cloned/pulled and a store-backed health check passes;
- personal repositories are owned by the user, not the organization;
- no `.env`, copied private key, admin credential, token, or personal content
  appears in manifests, briefs, repositories, logs, or Admin output;
- a second run is idempotent and a dirty user-owned file is held, not destroyed.

Store this evidence against PRD-14/TASK-147 before declaring Phase 6 complete.

## 7. Recovery

All setup steps are additive. A failed stage must return a resumable blocker and
leave already-passing stages intact. Revoke a compromised per-machine identity or
SSH key at its provider, then rerun User Setup. Never repair onboarding by copying
another machine's private key, personal repository, keychain record, or `.env`.
