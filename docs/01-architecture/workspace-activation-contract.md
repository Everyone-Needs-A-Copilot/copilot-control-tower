# Workspace activation contract

Workspace activation is the recurring end-user experience after organization
standup and person/device enrollment. It is not another ecosystem layer.

## The three operations

1. **Organization standup (Admin app).** Verify public foundations; discover,
   reuse, or privately create organization and department repositories; publish
   the non-secret user handoff. Admin never sees or creates personal content.
2. **Person/device enrollment (User app).** Discover, reuse, or privately create
   the signed-in person's private component repositories; establish on-device
   credentials; resolve and materialize the user's ecosystem.
3. **Workspace activation (User app, recurring).** Inspect approved local project
   roots. A configured project activates silently. A project with no shared
   Copilot setup gets one plain-language prompt. Personal preferences associate
   privately by opaque project id and never enter the shared project unless the
   user separately chooses to share them.

## State ownership

| State | Location | Purpose |
|---|---|---|
| Shared project declaration | `copilot.project.json` in the project | Portable selection of `claude` and/or `codex`; no ranks, repos, URLs, secrets, org topology, or machine paths |
| Generated install record | `copilot.lock.json` in the project | Component Sync's per-file ownership/version record; the declaration never substitutes for this evidence |
| Personal project association | machine-local private registry, keyed by a SHA-256 project id | Connects a canonical remote identity to the person's private profile seam without storing a path or remote URL |
| Organization/personal layers | their existing private ecosystem repositories and manifests | Remain outside the project; the project is self-contained shared context, not a new inheritance tier |

## CLI authority

`cc workspace --all --json` performs bounded discovery under explicitly
configured `projects.roots` plus the explicit project registry. It does not scan
the home directory or disk implicitly, follow symlinked directories, or treat an
arbitrary `.claude/` folder as proof of installation.

`cc workspace configure --project <path> --components <...>
--share-with-project --apply --json` repeats preflight before mutation, checks
every Claude and Codex target for collisions before the first write, invokes the
component-owned setup adapters, and writes the shared declaration only after
explicit installation markers exist. Existing paths block the operation; they
are never replaced. A declaration with missing installation evidence reports
`activation-required`, not `ready`.

Control Tower only invokes and decodes these versioned results. It does not scan
directories, normalize Git origins, choose products, install files, or infer
readiness.

During User Setup, a Codex user may choose one ordinary folder using the macOS
folder picker. `cc workspace approve-root --path <folder> --apply --json`
canonicalizes and records that explicit folder; symlinked or unavailable roots
are refused. The app shows only the folder's display name. Non-developers are
not asked to enumerate repositories or approve a code folder.

## End-user behavior

- `ready`: no project prompt. If an opaque project id is available, the User app
  associates the private profile locally without writing to the shared repo.
- `setup-available`: show one prompt: “Copilot is available for _Project_.” The
  only action is “Set up this project.”
- `activation-required`: show “Finish Copilot setup for _Project_ on this Mac.”
- `blocked`: explain in plain language that existing setup needs review, confirm
  that nothing changed, and offer a retry. Never expose ranks, repository
  topology, manifests, Git commands, or raw filesystem errors.

## Security and recovery

- Canonical remote identities are normalized and hashed. JSON output and the
  personal registry never contain the raw remote, embedded credentials, or a
  local project path in the personal association.
- Projects without an origin remain `local-only`; the CLI never fabricates a
  portable identity.
- Setup is additive. All selected installers preflight before mutation. A
  collision blocks all selected products before any one of them writes.
- Personal-to-project promotion is a separate future explicit action. Nothing
  in recurring activation commits, pushes, or promotes private content.
- The app stays silent for healthy state and never converts a partial setup into
  a successful result.
