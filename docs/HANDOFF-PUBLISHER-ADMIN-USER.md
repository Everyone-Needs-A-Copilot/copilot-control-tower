# Developer Handoff: Publisher, Admin, and User Journeys

This handoff is for the next developer picking up Control Tower after the
publisher setup work. It summarizes what changed, what to do next, and what
comes after that across the three roles the product now has to serve.

> **Model note (read before the rest):** since this handoff was first written,
> an audit found the product model needed correction: the Copilot Solutioning
> Ecosystem (CSE). See [`docs/reference/cse-alignment-decisions.md`](reference/cse-alignment-decisions.md)
> and [`docs/reference/copilot-solutioning-ecosystem.md`](reference/copilot-solutioning-ecosystem.md),
> which now govern, and the reframed [`docs/03-design/three-role-journeys.md`](03-design/three-role-journeys.md).
> The Publisher section below is unaffected (it is about signing the binary).
> The **Admin section is rebuilt** around GitHub repos, team-grant entitlement,
> the central shared secret store, and the ecosystem seed: MDM (`.mobileconfig`,
> Jamf/Kandji/Intune, a forced/managed device domain, a fleet console as
> Admin's center of gravity) is dropped completely as a mechanism. The **User
> section is updated** to drop the managed/unmanaged (MDM) install-lane split
> in favor of one self-install path, plus department discovery/join and a
> shared-vs-personal integration split. Code-level rename of "product" to
> "component" (the CSE tooling axis) is still pending; that is real work,
> deferred to the build phase, not done by this doc pass.

- **Publisher:** release owner who produces a signed/notarized artifact.
- **Admin:** IT/fleet operator who deploys and governs that artifact.
- **User:** non-technical person who receives a working, honest Control Tower.

Current baseline while writing this:

- Branch: `app-build`
- Last committed baseline: `dfc269d Add guided publisher setup workflow`
- Local uncommitted work exists in:
  - `scripts/publisher_setup.swift`
  - `docs/07-contributing/publisher-release-runbook.md`
  - `docs/HANDOFF-PUBLISHER-ADMIN-USER.md` until this handoff is committed

Those uncommitted files add the next publisher step: the setup app now offers
to build, sign, notarize, and staple the artifact instead of asking the
publisher to copy terminal commands.

## Product Rule To Preserve

Every role needs a no-dead-end flow.

- Publisher should not have to become a shell user after credentials are ready.
- Admin should not have to hand-edit YAML or guess what a red preflight item
  means.
- User should not be asked to approve or understand anything outside their own
  data.

The role boundary matters. Publisher authority is release-signing authority.
Admin authority is org standup authority: repos, teams (entitlement), the
central shared secret store, and the ecosystem seed. User authority is personal
data and explicit sign-in. Do not blur these credentials or decisions.

## Files To Read First

- `docs/reference/cse-alignment-decisions.md` and
  `docs/reference/copilot-solutioning-ecosystem.md` for the governing model
  (read these first; they correct several assumptions below).
- `docs/03-design/three-role-journeys.md` for the reframed Publisher/Admin/User
  journeys this handoff now matches.
- `SOUL.md` for product boundaries and the Publisher/Admin/User mental model.
- `docs/reference/publisher-admin-experience.md` for the Publisher/Admin split
  (Publisher content still accurate; Admin content predates the CSE realignment).
- `docs/07-contributing/publisher-release-runbook.md` for publisher setup.
- `docs/06-deployment/README.md` and `docs/06-deployment/standup-runbook.md`
  for what Admin mode has shipped vs. designed (both predate the realignment;
  read against `three-role-journeys.md` §2, not at face value).
- `docs/08-observability/operator-guide.md` for observability caveats (also
  predates the realignment: the fleet dashboard is no longer Admin's center
  of gravity).
- `scripts/publisher_setup.swift` for the current publisher setup app.

## Publisher Journey

### What Exists Now

Publisher setup is repo-local tooling, not a normal customer app surface.

Relevant files:

- `Publisher Setup.app/`
- `scripts/publisher_setup.swift`
- `scripts/setup-publisher.sh`
- `scripts/publisher-setup.command`
- `scripts/sign.sh`
- `scripts/notarize.sh`
- `docs/07-contributing/publisher-release-runbook.md`

The app now guides a publisher through:

1. Apple-side prerequisite education.
2. Developer ID Application identity detection.
3. Team ID extraction.
4. Apple notarization profile storage via `xcrun notarytool`.
5. Local `.env.release.local` generation with owner-only permissions.
6. Success/failure takeover screens.
7. Uncommitted local change: run build/sign/notarize/staple from the app.

The publisher setup app intentionally does not create Apple credentials. It
teaches the publisher how to create them and then uses the credential once to
store a local Keychain profile.

### Immediate Next Work

Finish and verify the uncommitted app-run publishing flow.

Acceptance target:

1. Open `Publisher Setup.app`.
2. Complete setup with a real Developer ID certificate and real app-specific
   password.
3. Click **Build, Sign, and Notarize**.
4. App shows live progress, not terminal instructions.
5. Failure shows a copyable log with the first failed command.
6. Success shows an Admin handoff screen naming the `.app` and `.dmg`.

Validation already run for the uncommitted change:

- `swiftc -typecheck scripts/publisher_setup.swift`
- `git diff --check`
- `bash -n` for setup/app wrapper scripts
- `plutil -lint Publisher Setup.app/Contents/Info.plist`
- app bundle launch smoke

Still needed:

- Real end-to-end run of **Build, Sign, and Notarize** on Pablo's Mac.
- Confirm the expected DMG path after `npm run tauri build`; adjust the app if
  Tauri emits a versioned DMG filename rather than
  `Copilot Control Tower.dmg`.
- Confirm failure logs are readable and copy cleanly.
- Commit the uncommitted publisher runner/doc changes after the real run.

### What Comes After That

Move the proven local publisher path into CI without weakening custody.

Work items:

- Decide CI credential shape: local Keychain profile is for local publisher
  Macs; CI should use App Store Connect API-key secrets.
- Replace any placeholder update-feed/minisign values only after two-of-N
  production custody is decided.
- Ensure CI publishes the same artifact shape the Admin flow expects.
- Keep manual commands in the runbook as fallback/debug only, not the main
  publisher path.

Do not give Admin users Developer ID private keys, notarization passwords, App
Store Connect private keys, or update-manifest private keys.

## Admin Journey

**This section is rebuilt for the CSE realignment.** The prior version of this
handoff built the Admin journey around MDM (a `.mobileconfig` generator, a
managed-key registry, a fleet dashboard). That mechanism is dropped completely
(D4). The center of gravity is now: stand up the four-tier component repos,
grant team access (entitlement), configure the central shared secret store,
and author the ecosystem seed. No MDM, no fleet console, no forced-key domain.
See `docs/03-design/three-role-journeys.md` §2 for the full sequence (A0
through A9) this section summarizes.

### What Exists Now

Admin mode is part of this repo and product, not a separate repo.

Real shipped pieces (built under the pre-realignment MDM design; still real
code, but the mechanism they implement is superseded, not the target):

- managed-key registry: `src-tauri/src/managed/keys.rs`
- managed login item: `src-tauri/src/loginitem/{mod,smappservice}.rs`
- deprovision trigger and routing: `src-tauri/src/routing/` and
  `src-tauri/src/deprovision/` (the render-not-compute pattern here is still
  correct and reusable; only the entitlement source changes, from MDM
  enrollment to GitHub repo access)
- `.mobileconfig` generator: `src-tauri/src/mobileconfig/{mod,generator}.rs`
  (superseded; not part of the corrected Admin path)
- fixture-backed fleet frontend: `src/render/fleet.ts`, `src/fleet.html`,
  `src/dev-fixtures/fleet/*.json` (fleet observability is no longer Admin's
  center of gravity; treat this as a possible secondary surface, not the
  Admin build target)

Not built, and now scoped to the corrected model:

- GitHub repo topology (Foundation/Org/Department/Personal repos, org-owner
  creation, team grants): design only, no in-app flow
- seed generator (`ecosystem.yml`): not built; no `src-tauri/src/seed/`
- preflight validation (repos exist, seed parses, policy signed, secret store
  reachable): not built; no `src-tauri/src/preflight/`
- central shared secret store connection (Infisical/OpenBao, GitHub-team
  scoped): org decision, no code gap yet
- access-policy signer flow (CODEOWNERS/rulesets on executable paths): design
  only
- guided deprovision action (revoke GitHub repo access + rotate shared-secret-
  store tokens): mechanism defined, no in-app action yet

Admin starts after Publisher produces a signed/notarized/stapled artifact.

### Immediate Next Work

Turn the Admin journey into the next guided product surface, built around
repos/teams/secret-store/seed, not a profile/fleet loop.

The first useful Admin milestone should be a real GitHub-topology + seed loop:

1. Prerequisites & contacts screen: confirm org/config authority; name the
   GitHub org owner and an `AdminContact` for safety escalation.
2. GitHub topology guide, teach + verify: walk the Admin through creating
   `copilot-org` and `copilot-dept-<unit>` repos, setting org base-read, and
   granting dept teams read/write (this **is** the entitlement, D3).
3. Seed generator: author `ecosystem.yml` (components/depts/pins/auth/
   policy_signers/telemetry) in-app and open the PR. This is the single
   highest-value build (closes the doc's biggest gap).
4. Setup verification: red/green over repos, teams, the secret store, and the
   seed, each red item names its owner:
   - Publisher owns artifact/signing/version issues.
   - Admin owns repo/team/secret-store/policy issues.
   - User owns only personal sign-in or dirty personal work.

Start with the smallest real path:

- Build the GitHub-topology teach + verify screen first (closes the "who to
  ask, in what order" gap).
- Add the seed generator next; it is the thing that unblocks everything after
  it (repos and teams can be stood up by hand meanwhile).
- Show missing/invalid seed fields before opening the PR.

Do not start by building a broad dashboard. Admin cannot stand up an org until
repos, teams, the secret store, and the seed are concrete.

### What Comes After That

After Admin can produce and verify the seed, wire the rest of the loop:

1. "Who authors" decision flow: choose authors per department, grant team
   write, provision each author's own on-device SSH key (never shared-store
   material).
2. Central shared secret store setup guide: connect Infisical/OpenBao, scope
   access by GitHub-team membership; deliver the endpoint via inherited org
   repo config (D4/D6), never an MDM domain.
3. Access policy signer flow: sign the capability policy, set CODEOWNERS/
   rulesets on the executable paths.
4. Guided deprovision action: revoke the leaver's GitHub repo access and
   rotate shared-secret-store tokens; no remote wipe (accepted residual for
   the target org size).
5. If fleet observability is still wanted as a secondary surface: a real
   collector integration behind the same worst-wins, no-computed-score rules
   that already govern the fixture-backed frontend.

Keep the Admin surfaces honest:

- no computed fleet health score, no blended verdicts (if fleet observability
  ships at all)
- per-machine or per-repo state only
- safety escalation points to `AdminContact`
- fixture-only or design-only surfaces must remain labeled as such

## User Journey

**This section is updated for the CSE realignment.** The prior version split
User onboarding into a managed (MDM zero-touch) lane and an unmanaged
(double-click) lane. MDM is dropped completely (D4): there is **one** install
path, self-install of the signed, notarized `.dmg`, not two lanes. Two new
surfaces are added: department discovery/join (D7.1) and a distinct register
for entitled shared integrations versus personal sign-in (D7.2). See
`docs/03-design/three-role-journeys.md` §3 for the full sequence (U0 through
U12) this section summarizes.

### What Exists Now

The user is the non-technical recipient of the system. In `SOUL.md`, this is
Bob: change-averse, safety-sensitive, and not a reliable actor for IT or
release decisions.

Relevant shipped/designed surfaces include:

- tray/status rendering from CLI truth
- first-run wizard DTOs and frontend contracts in `src/types.ts`
- Bob prompt/notice contracts in `src/types.ts`
- routing rules that keep IT/release decisions away from Bob

Not built, and now scoped to the corrected model:

- department discovery + join: nothing surfaces which departments Bob is
  entitled to (by GitHub repo access) or lets him join one
- the shared-vs-personal integration split: the current model conflates
  personal sign-in (device-flow) with entitled shared integrations that would
  be provisioned centrally from the shared secret store
- personal-key multi-machine sync: Bob still hand-copies `.env` between his
  own machines

The user experience target is:

- one self-install path (double-click the signed `.dmg`); never asked to
  install a profile or judge trust
- honest status
- join his own department without asking anyone, validated by his own GitHub
  repo access
- sign-in only when needed, and clearly distinguished from shared integrations
  that just appear because he's entitled to them
- personal dirty-work decisions only when genuinely user-owned
- no raw Git/VCS errors
- no release, org-config, or IT decisions pushed to the user

### Immediate Next Work

After Publisher and Admin have a real artifact/org-standup path, validate the
actual user first run.

1. **First run:** wizard asks only what Bob can answer, never exposes org
   deployment concerns, and never asks him to install a profile.
2. **Department discovery + join:** surface the departments Bob is entitled
   to (validated by his GitHub repo access) and sync the selected layer on
   join.
3. **Shared-vs-personal integrations:** entitled shared integrations
   (Salesforce, Workday, Microsoft) already appear connected, no sign-in
   prompt; personal sign-in (Slack, etc.) stays a distinct, separately
   labeled device-flow register.

Acceptance target:

- A user can reach a working state without opening Terminal.
- Bob can join a department he's entitled to without asking anyone.
- Missing org/admin configuration routes to Admin, not User.
- Missing release trust routes to Publisher/Admin, not User.
- User-facing copy never exposes raw command output unless it is genuinely the
  user's own recoverable action.

### What Comes After That

Once first-run, department join, and the integration split work on real
machines:

1. Personal-key multi-machine sync: Bob's own keys follow him to a second
   machine, ending the `.env` hand-copying (D7.3, still open on carrier design).
2. Exercise updates from the publisher-produced artifact.
3. Confirm crash/watchdog behavior on a real install.
4. Confirm safety escalation reaches AdminContact without requiring user
   action.
5. Confirm user prompts remain limited to sign-in, a new department to join,
   and dirty personal work.
6. Run a departure/deprovision scenario (GitHub access revoked, shared-secret-
   store tokens rotated) and verify user data boundaries; already-synced
   content is not remotely wiped (accepted residual, D4).

The final user success signal is not "the app installed." It is: the user has
the Copilot ecosystem ready and self-healing, joined his own department
without asking anyone, and never needed to understand the release chain, org
config, Git, YAML, or terminal commands.

## Recommended Next Developer Sequence

1. Finish the uncommitted publisher app-run publishing flow.
2. Commit it after a real end-to-end artifact run or a documented blocker.
3. Update `docs/reference/publisher-admin-experience.md` so Publisher step 7
   says the app runs publishing directly, not "run commands."
4. Start Admin with the GitHub-topology teach + verify screen and the seed
   generator, not fleet dashboard polish (the fleet dashboard is no longer
   Admin's center of gravity, D4).
5. Stand up a real test GitHub org (repos + teams) as soon as the seed
   generator exists, and validate the central shared secret store connection
   against it.
6. Only after Admin can stand up an org, validate the User first-run,
   department-join, and tray flows.

## Known Risks

- The publisher app currently assumes fixed artifact paths. Tauri may emit a
  versioned DMG name; verify before relying on the Admin handoff screen.
- Admin mode has a strong design, but much of the standup path is still
  designed/not built, and the design itself just changed (MDM dropped; repos/
  teams/secret-store/seed is the new center of gravity). Re-check any Admin
  work in flight against `docs/03-design/three-role-journeys.md` §2 before
  continuing it.
- Fleet dashboard is fixture-backed and no longer the Admin build target; do
  not treat it as live observability or prioritize it.
- Two-of-N signing custody is not production-ready.
- No real IT operator has validated Admin mode yet. Keep the hypothesis label
  until one has.
- Department discovery/join, the shared-vs-personal integration split, and
  personal-key multi-machine sync (D7) are net-new surfaces with no shipped
  code; do not assume partial credit from the old managed/unmanaged wizard
  design.

## Definition Of Done For The Whole Chain

Publisher done:

- signed, notarized, stapled `.app`/`.dmg` exists
- publishing log is copyable
- no Developer ID or notarization secret leaves publisher custody

Admin done:

- the four-tier component repos exist with team-grant entitlement wired
- the central shared secret store is connected and scoped by GitHub team
- a signed `ecosystem.yml` seed exists and preflight explains every blocker
  (repos, teams, secret store, seed, each red item names its owner)
- safety escalation reaches `AdminContact`

User done:

- the user gets a ready system with no terminal work from one self-install
- the user joins his own department without asking anyone, validated by his
  own GitHub repo access
- the user can tell his personal sign-ins apart from shared integrations that
  are just there because he's entitled to them
- app never asks the user to judge Publisher/Admin decisions
- status remains honest and recoverable
