# Ground-up Claude and Codex installation

This is the Phase 6 implementation and acceptance reference for an ENAC
installation with no department layer. The aggregate onboarding transaction is
implemented; signed distribution, published foundation signer trust anchors,
and the two-machine live proof remain. For the exact Admin-first, laptop-second
operator sequence, use
[`admin-first-two-machine-setup-runbook.md`](admin-first-two-machine-setup-runbook.md).
Do not bypass a remaining trust gate with hand-written layer YAML and then call
the machine onboarded.

There are three separate experiences: Admin establishes organization resources;
User Setup enrolls the person and device; recurring workspace activation checks
projects under approved roots and silently applies already-declared setup. A
project is self-contained shared context, not a fourth inheritance layer.

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
bash scripts/tests/test_admin_app_bundle.sh
bash scripts/tests/test_user_app_bundle.sh
```

The build commands produce the double-clickable development artifacts at
`build/Copilot Control Tower Admin.app` and
`build/Copilot Control Tower.app`. They are ad-hoc signed for local testing.
Distribution still requires the Developer ID/notarized pipeline and its
owner-controlled credentials.

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

The engine and Admin development app now support this contract offline. The app
collects the public client id (never the secret); the engine refuses missing or
conflicting organization identity before mutation, emits independent Claude and
Codex pins plus the personal handoff, and verifies `github-app` and
`personal-handoff` as separate rows. Live-org execution is still required before
this section is accepted end to end.

## 5. Run User Setup (aggregate transaction implemented)

The lower-level plan/apply slice can safely inventory and create the signed-in
user's missing private component repositories:

```bash
cc onboard --scope personal --components claude,codex,knowledge,cli --json
cc onboard --scope personal --components claude,codex,knowledge,cli --apply --json
```

Plan is read-only. Apply repeats the complete preflight before creation. An
existing private repository is reused; a public collision or unreadable target
blocks the transaction; only an explicit GitHub 404 is treated as missing.
The aggregate transaction below uses that repository safety contract, seeds the
rank-10 packages, and continues through device and materialization setup.

The app does not require a clean machine. Before Apply, User Setup shows every
recognized item as **Keep**, **Add**, **Move safely**, or **Complete**. A
recognized earlier manifest is merged with the missing Claude/Codex layers, so
existing CLI or other product layers remain in place. A local rollback copy is
written before a move or repair. Unfamiliar personal content, an unmanaged SSH
alias, or a conflicting manifest is shown as **Needs review** and stops the
complete transaction before mutation.

The implemented single transaction is:

```bash
cc onboard --org Everyone-Needs-A-Copilot --products claude,codex --json
```

It:

1. performs a complete read-only inventory and renders the adoption plan;
2. authenticates the individual through the organization's device-flow client;
3. creates or selects the user's private Claude and Codex personal repositories;
4. generates independent on-device SSH credentials and registers only public keys;
5. adopts or safely repairs the unified manifest without dropping existing products;
6. provisions a scoped per-machine store identity into the OS keychain;
7. resolves winners by `(product, dimension, item)`;
8. materializes only to product-specific allowlisted targets;
9. coordinates CLI mirror sync and runs doctor;
10. returns opaque personal provenance and the three-layer result for each product.

The transaction is implemented and test-covered. A machine is still not a valid
ground-up proof until that transaction runs live with published trusted
foundation signatures and returns healthy. Do not hand-place a unified manifest
or reuse an administrator credential to make the status appear green.

## 6. Acceptance evidence

### Recurring project activation (implemented development slice)

After User Setup configures one or more approved project roots:

```bash
cc workspace approve-root --path /absolute/path/to/projects --apply --json
cc workspace --all --json
cc workspace configure --project /absolute/path/to/project --components auto --share-with-project --apply --json
```

The first command is read-only and discovers Git projects even when they have no
Copilot lock yet. The second performs a complete collision preflight, activates
the installed Claude/Codex foundations additively, writes
`copilot.project.json` only after installation proof exists, and privately
associates the canonical project identity. Existing project setup is never
replaced. Projects without a remote remain local-only. Control Tower runs these
verbs and stays silent for `ready`; it prompts only for `setup-available` or
`activation-required`.

This recurring project flow does not complete the separate aggregate person and
device enrollment transaction described above. It assumes the public
foundations are installed and does not create organization/personal repositories,
mint SSH or store credentials, or resolve the three-layer product stack.

## 7. Acceptance evidence

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

## 8. Recovery

All setup steps are additive or rollback-backed. A failed stage must return a
resumable blocker and leave already-passing stages intact. Manifest repair and
migration keep the prior bytes under the manifest directory's
`.copilot-control-tower-backups/<sha256>/` folder. Revoke a compromised
per-machine identity or SSH key at its provider, then rerun User Setup. Never
repair onboarding by copying another machine's private key, personal repository,
keychain record, or `.env`.

## 9. Clean-laptop reset prompt

Use this only after the signed replacement installer and the Admin/User workflow
have passed on the first machine. Remote organization and personal repositories
are durable source-of-truth and must not be deleted for a device reset.

```text
I need to reset this laptop's local Copilot development environment before a
ground-up Phase 6 onboarding proof.

Work in two gates. Gate 1 is read-only: inventory Claude Copilot, Codex Copilot,
the cc CLI, Copilot Control Tower Admin/User apps and support files, local ENAC
checkouts/mirrors, launch agents/login items, project links, SSH aliases/keys,
and relevant keychain entries. Resolve symlinks and executable provenance.
Classify every item as managed Copilot state, potentially user-authored/dirty
data, unrelated data, or unknown. Check git status for every repository. Confirm
that the replacement installer/source checkout is available. Produce an exact
reset plan with explicit absolute paths and commands, then stop for my approval.

Gate 2 begins only after I explicitly approve that exact plan. Do not delete or
change any GitHub repository, organization setting, OAuth App, Infisical secret,
remote SSH key, or other remote resource. Do not touch unrelated Claude/Codex
configuration, projects, source repositories, or user-authored files. Move
approved local targets into one timestamped quarantine directory in the Trash
instead of using rm; preserve metadata and write a restore manifest. Remove only
approved Copilot launch/login registrations and local keychain records. Never
print secret values. Verify the named paths are absent/inactive, verify Codex,
Claude Code, git, gh, and the system compiler still resolve as expected, and
report the quarantine path plus exact rollback commands. Do not reinstall or
onboard until I give a separate instruction.
```

After reset, run Admin Setup only on an owner-authorized machine to verify/create
organization resources. Then run User Setup separately on each computer as the
individual; it must rediscover and reuse existing private personal repositories
rather than create duplicates.
