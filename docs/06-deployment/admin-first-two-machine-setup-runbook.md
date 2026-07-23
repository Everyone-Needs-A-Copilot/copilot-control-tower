# Admin-first two-machine setup runbook

Use this runbook to establish the organization from the current Mac, then
reset and enroll a second Mac as a user. It is the operator sequence for the
Phase 6 live proof with Claude Copilot and Codex Copilot and no department
layer.

The two machines have different jobs:

| Machine | App and identity | What it is allowed to manage |
|---|---|---|
| Current Mac | Control Tower **Admin**, signed in as a GitHub organization owner | The organization's four private `-internal` repositories, organization setup, and optional departments |
| Laptop | Control Tower **User**, signed in as the individual | That person's private Claude and Codex repositories, a new per-device key, personal materialization, and local projects |

Admin Setup must never create or access a personal repository. User Setup must
never create an organization or department repository.

## Important readiness notice

You can run the Admin portion now from the double-clickable development app.
**Do not clean the laptop until the handoff gate in Part 2 is green.** As of
2026-07-23, that gate is not green:

- the Control Tower and Copilot branches containing the final onboarding work
  are not all available from their remotes;
- the pinned `claude-copilot` and `cli-copilot` commits used by the development
  installer are not yet on their remotes;
- the public Claude and Codex foundation releases do not yet have approved
  signer fingerprints compiled into `cc`; and
- there is no signed and notarized Control Tower distribution artifact yet.

These are release and live-proof gates, not missing Admin/User workflow code.
The Admin development app is self-contained and can be exercised locally
without Terminal. A wiped laptop does not yet have a fully recoverable, trusted
User installation path.

## Result to expect

With no departments, Admin Setup will check and then create or reuse these four
repositories in the GitHub organization:

- `knowledge-copilot-internal`
- `cli-copilot-internal`
- `claude-copilot-internal`
- `codex-copilot-internal`

All four must be private. Claude and Codex receive organization layer packages
at rank 30. Knowledge and CLI are shared supporting repositories, so there are
four organization repositories rather than six.

On the laptop, User Setup will check and then create or reuse these repositories
in the authenticated person's GitHub account:

- `claude-copilot-private`
- `codex-copilot-private`

The final product stack on that laptop is:

| Product | Personal | Organization | Foundation |
|---|---:|---:|---:|
| Claude | rank 10 | rank 30 | rank 40 |
| Codex | rank 10 | rank 30 | rank 40 |

## Part 1 — Set up the organization on this Mac

### 1. Open Admin

In Finder, open:

```text
copilot-control-tower
└── build
    └── Copilot Control Tower Admin.app
```

Double-click **Copilot Control Tower Admin**. The Admin window opens directly.
You do not open Terminal, install Homebrew packages, or run prerequisite
commands.

The development app is ad-hoc signed for this Mac. A distributed build still
requires the Developer ID and notarization gate described in Part 2.

### 2. Let Admin check readiness

Admin includes its required local tools inside the app. When you reach **Get
this Mac ready**, it automatically checks:

- that the tools packaged inside Admin start correctly;
- whether a GitHub account is connected;
- whether GitHub has granted organization-setup permission; and
- whether the connected account is an active owner of the organization you
  entered.

If GitHub sign-in or permission is missing, select **Authorize GitHub**. Admin
opens GitHub's browser authorization, waits for it to finish, and checks again.
It never displays a shell command.

Two owner-controlled facts cannot be installed or invented by the app:

- An existing organization owner must create the organization and grant owner
  status. If that is missing, Admin identifies it and opens the organization
  settings.
- An organization owner must create the organization's OAuth App and enable
  device flow. Select **Open OAuth App settings**, complete that GitHub form,
  and paste only its public 20-character Client ID into Admin. Never paste its
  client secret.

These are authority decisions in GitHub, not software prerequisites on the Mac.

### 3. Complete the Admin wizard

Walk through the screens in this order:

1. **Orientation** — confirm this is organization setup, not personal setup.
2. **Prerequisites** — review what Admin will check automatically.
3. **Contacts** — enter the organization contacts.
4. **Get this Mac ready** — enter the organization, authorize GitHub if asked,
   open the OAuth App settings if needed, and continue after every row is
   checked.
5. **Describe your organization** — enter the exact organization login, select
   both Claude and Codex, and add no departments.
6. **Integrations** — declare only the integrations that actually exist.
7. **Secret store** — choose Infisical and enter its non-secret endpoint,
   workspace/project ID, environment, and absolute secret path. Do not paste
   secret values.
8. **Review setup** — read the complete repository inventory before
   approving anything.

The Review screen must list exactly the intended targets. For every target,
Admin performs a read-only check first:

- an existing private repository is reused;
- only an explicit GitHub `404` is treated as missing and eligible for private
  creation;
- a public repository, an unreadable repository, conflicting organization
  identity, or unfamiliar content blocks the transaction before creation.

If the inventory is correct and unblocked, select **Set up organization**.
The engine repeats the complete preflight before it mutates GitHub.

### 4. Review any setup pull request

An empty organization repository can receive its initial setup directly. If
the repository already has content, Admin uses the fixed `copilot-standup`
branch and opens or updates a pull request instead of writing to the default
branch.

Open the affected repository in GitHub, review the additive `ecosystem.yml`
change, and merge the pull request. Do not merge a change with an unexpected
organization, product, department, store pointer, or foundation reference.

The Setup check can remain red until this pull request is merged.

### 5. Run the Setup check

Continue in Admin and run **Setup check**. The successful state is:

> Everything is set up and verified.

That means `must_fix` is `0` and `unknown` is `0`. A skipped private-repository
review-protection check on a GitHub plan that does not support it is not a
failure; a failed or unknown row is a stop condition.

### 6. Prove the Admin operation is repeatable

Return to **Review setup** and select **Set up organization** one more time.
Admin repeats the read-only inventory and full preflight. The second run must
reuse the same repositories and report only already-present, updated, or skipped
work. It must not create duplicate repositories or overwrite unfamiliar content.

Admin setup is complete only when all of the following are true:

- the Setup check has `must_fix: 0` and `unknown: 0`;
- all four organization repositories exist and are private;
- any `copilot-standup` pull request has been reviewed and merged;
- a second Admin run is safe and idempotent; and
- no personal repository, token, private key, client secret, or `.env` was
  added to the organization setup.

## Part 2 — Handoff gate before cleaning the laptop

Do not reset the laptop until every item in this section is true.

### Organization gate

- Part 1 is completely green.
- The OAuth App has device flow enabled.
- The Infisical organization scope exists and the intended laptop identity can
  be provisioned without sharing an organization-wide credential.

### Replacement-path gate

- The exact Control Tower source or signed installer is stored somewhere other
  than the laptop.
- The exact `cc` and `copilot` CLI commits are reachable from the laptop after
  reset.
- Claude Code, Codex CLI, Git, GitHub CLI, and Python 3 have a known reinstall
  path.
- Recovery does not depend on an unpushed branch, an uncommitted file, or a
  private key that exists only on the laptop.

For the current development proof, these refs must be remotely reachable:

| Repository | Required ref |
|---|---|
| `copilot-control-tower` | `6f2d572f0bdb7169774aacb4287d4a9782c7c780` or a later reviewed commit containing it |
| `claude-copilot` | `3dcb5684c196d41caf5b727dba17d74dfa7c7ecd` |
| `cli-copilot` | `c6e1e02fc4e0e4db3d1413ed6e369367fa7bd9fc` |
| `codex-copilot` | `87837ef2f2f208b6d76bd5506ea650d0171a5a6a` or a later reviewed release containing it |

### Trust gate

For a complete Phase 6 product proof, not just a source-development exercise:

- the Control Tower User app is signed and notarized;
- Claude and Codex foundation releases use approved Git commit signatures;
- the corresponding signer fingerprints are compiled into the distributed
  `cc`; and
- the release artifacts and checksums are available from a clean machine.

Until this trust gate is satisfied, `cc onboard --apply` is expected to stop
when executable foundation content cannot be verified. Do not bypass that
check, add an arbitrary signer, or hand-copy materialized content to make the
machine appear healthy.

## Part 3 — Clean the laptop safely

Use a quarantine reset, not a blind delete. Paste the following prompt into
Codex or Claude Code on the laptop:

```text
I need to reset this Mac's local Copilot development environment before a
ground-up Copilot Control Tower onboarding proof.

Work in two gates.

Gate 1 is read-only. Inventory Claude Copilot, Codex Copilot, the cc CLI, the
copilot CLI, Copilot Control Tower Admin/User apps and support files, local ENAC
checkouts and mirrors, launch agents or login items, project links, managed SSH
aliases and keys, and relevant Keychain entries. Resolve symlinks and executable
provenance. Check git status for every repository. Classify every item as
managed Copilot state, potentially user-authored or dirty data, unrelated data,
or unknown. Confirm that the replacement installer or remote source refs are
available. Produce an exact reset plan with explicit absolute paths and
commands, then stop for my approval.

Gate 2 begins only after I explicitly approve that exact plan. Do not delete or
change any GitHub repository, organization setting, OAuth App, Infisical secret,
remote SSH key, or other remote resource. Do not touch unrelated Claude/Codex
configuration, projects, source repositories, or user-authored files. Move only
the approved local targets into one timestamped quarantine directory in the
Trash instead of using rm. Preserve metadata and write a restore manifest.
Remove only the approved Copilot launch/login registrations and local Keychain
records. Never print secret values. Verify that the named paths are absent or
inactive; verify that Codex, Claude Code, git, gh, Python 3, and the system
compiler still resolve as expected; and report the quarantine path plus exact
rollback commands. Do not reinstall or onboard until I give a separate
instruction.
```

Read the Gate 1 inventory. Approve Gate 2 only if every target is explicit and
the replacement-path gate in Part 2 remains green. This reset is local-only:
the organization and personal GitHub repositories must survive so User Setup
can discover and reuse them.

## Part 4 — Install Control Tower on the clean laptop

### 1. Restore the host prerequisites

Use the official installers for any missing host tools, then verify them:

```bash
git --version
python3 --version
gh --version
claude --version
codex --version
```

Do not copy a GitHub token, SSH private key, Infisical credential, `.env`, or
Keychain record from the first Mac. The laptop must receive its own device
credentials during User Setup.

### 2. Obtain the approved Control Tower build

For the production proof, install the signed and notarized User app and verify
that macOS opens it without bypassing Gatekeeper.

For the temporary development proof, clone the now-published Control Tower ref
and confirm its provenance before building:

```bash
git clone https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git
cd copilot-control-tower
git checkout --detach 6f2d572f0bdb7169774aacb4287d4a9782c7c780
git rev-parse HEAD
```

Do not use this development route until the commit is actually reachable from
the remote.

### 3. Install the pinned development CLIs

Skip this step when the signed User distribution already contains the approved
CLIs. From the development Control Tower checkout, run the read-only plan first:

```bash
./scripts/install-test-clis.sh --json
```

Proceed only when it reports that the pinned CLIs can be installed without
replacing unrelated `cc` or `copilot` commands:

```bash
./scripts/install-test-clis.sh --apply --json
"$HOME/.local/bin/cc" --version
"$HOME/.local/bin/copilot" --help
```

The installer refuses unmanaged command collisions and partial managed
installs. Inspect and quarantine a collision; do not overwrite it.

### 4. Build and open the User app for the development proof

```bash
bash scripts/build-user.command --build-only
bash scripts/build-user.command
```

The second command launches the development User app. Keep the terminal open.

## Part 5 — Run User Setup on the laptop

Complete the User wizard with the individual's GitHub account:

1. Connect GitHub through the organization's device-flow OAuth App.
2. Let **Detect** inventory the organization handoff, the signed-in person's
   private repositories, this device, the six intended layers, and current
   health.
3. Include both Claude and Codex.
4. Skip departments because this organization currently has none.
5. Review integrations and continue to **Set up**.
6. Approve the explicit setup action.
7. Continue only when **Verify** reports that everything checks out.

User Setup performs one aggregate transaction. It:

- rechecks both personal repository names before mutation;
- reuses an existing private repository;
- creates a repository private only when GitHub explicitly confirms it is
  missing;
- blocks on public, unreadable, or unfamiliar-content collisions;
- generates a new Ed25519 key on this laptop and registers only the public key;
- writes bounded `github-personal` and `github-work` SSH aliases without
  replacing unrelated SSH configuration;
- provisions a scoped, revocable Infisical identity into this laptop's
  Keychain;
- writes the six-layer product-aware manifest;
- materializes Claude and Codex only into their approved native targets;
- installs the verified Codex Copilot plugin through Codex's native marketplace;
  and
- finishes by running doctor.

If Setup enters a holding state, stop and fix the named condition. Re-run the
same transaction afterward; it is designed to resume safely.

## Part 6 — Acceptance checks on the laptop

Run the aggregate transaction a second time to prove it is repeatable:

```bash
"$HOME/.local/bin/cc" onboard \
  --org auto \
  --products claude,codex \
  --apply \
  --json

"$HOME/.local/bin/cc" doctor --json
codex plugin list
```

Accept the laptop only when:

- aggregate onboarding reports `ready`;
- its layer report contains personal rank 10, organization rank 30, and
  foundation rank 40 for both Claude and Codex;
- doctor reports `healthy`;
- Codex lists the Codex Copilot plugin;
- the two personal repositories are private and owned by the individual;
- the four organization repositories remain private and owned by the
  organization;
- a fresh laptop-specific public key is registered while its private half never
  left the laptop;
- the scoped store identity works and no organization-wide bootstrap credential
  remains on the laptop;
- no `.env`, token, private key, or personal content appears in a shared
  repository, log, brief, or manifest; and
- the second run creates no duplicate repositories and overwrites no
  user-authored content.

After User Setup is healthy, choose the parent folder that contains local Git
projects when the User app offers project discovery. Existing configured
projects remain unchanged. A new clone or new local Git project under that
approved root is detected; Control Tower stays quiet when both copilots are
already present and prompts before additive setup when they are not.

## Recovery rules

- Never fix onboarding by copying another machine's private key, Keychain
  record, personal repository checkout, token, or `.env`.
- Never delete a remote organization or personal repository as part of a device
  reset.
- Revoke a compromised per-device SSH key or Infisical identity at its provider,
  quarantine its local state, and rerun User Setup.
- Preserve every safety hold. Resolve its cause; do not bypass signature,
  visibility, ownership, or unfamiliar-content checks.

Record the Admin verification JSON, laptop onboarding JSON, doctor JSON, exact
installed commits, and clean-machine observations as the evidence for Phase 6
`TASK-147`.
