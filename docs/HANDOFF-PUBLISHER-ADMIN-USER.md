# Developer Handoff: Publisher, Admin, and User Journeys

This handoff is for the next developer picking up Control Tower after the
publisher setup work. It summarizes what changed, what to do next, and what
comes after that across the three roles the product now has to serve:

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
Admin authority is fleet/configuration authority. User authority is personal
data and explicit sign-in. Do not blur these credentials or decisions.

## Files To Read First

- `SOUL.md` for product boundaries and the Publisher/Admin/User mental model.
- `docs/reference/publisher-admin-experience.md` for the Publisher/Admin split.
- `docs/07-contributing/publisher-release-runbook.md` for publisher setup.
- `docs/06-deployment/README.md` for what Admin mode has shipped vs. designed.
- `docs/06-deployment/standup-runbook.md` for the intended Admin journey.
- `docs/08-observability/operator-guide.md` for the fleet dashboard caveats.
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

### What Exists Now

Admin mode is part of this repo and product, not a separate repo.

Real shipped pieces include:

- `.mobileconfig` generator:
  `src-tauri/src/mobileconfig/{mod,generator}.rs`
- managed-key registry:
  `src-tauri/src/managed/keys.rs`
- managed login item:
  `src-tauri/src/loginitem/{mod,smappservice}.rs`
- deprovision trigger and routing:
  `src-tauri/src/routing/` and `src-tauri/src/deprovision/`
- fixture-backed fleet frontend:
  `src/render/fleet.ts`, `src/fleet.html`,
  `src/dev-fixtures/fleet/*.json`

Designed or partial pieces include:

- seed generator: not built; no `src-tauri/src/seed/`
- preflight validation: not built; no `src-tauri/src/preflight/`
- telemetry gate and transport: not built; schema type only exists
- live fleet backend: not built; `GET_FLEET_CMD` is reserved only
- two-of-N update verifier: dev-key sibling path exists, not active production
  self-update path

Admin starts after Publisher produces a signed/notarized/stapled artifact.

### Immediate Next Work

Turn the Admin journey into the next guided product surface.

The first useful Admin milestone should be a real preflight/generator loop:

1. Import or author org identity.
2. Generate an `ecosystem.yml` seed or at least validate a provided one.
3. Generate the `.mobileconfig`.
4. Run red/green preflight before any MDM push.
5. Explain every red item by owner:
   - Publisher owns artifact/signing/version issues.
   - Admin owns MDM/profile/org policy issues.
   - User owns only personal sign-in or dirty personal work.

Start with the smallest real path:

- Use the existing mobileconfig generator.
- Add a UI or command path that gathers required managed keys.
- Show missing/invalid keys before writing a profile.
- Produce a profile artifact the Admin can upload to Jamf/Kandji/Intune.

Do not start by building a broad dashboard. Admin cannot deploy a fleet until
seed/profile/preflight are concrete.

### What Comes After That

After Admin can produce and validate the profile, wire the operational loop:

1. Real MDM walkthroughs for Jamf, Kandji, and Intune.
2. A real enrolled-Mac validation pass that proves forced-domain keys take
   effect.
3. Live `get_fleet` backend or explicit collector integration.
4. Telemetry opt-in gate and transport.
5. Fleet dashboard backed by real collected fleet events.
6. Deprovision validation on a real managed Mac.
7. Update-feed and rollout-channel validation with the publisher artifact.

Keep the Admin dashboard honest:

- no fleet health score
- no blended computed verdicts
- per-machine state only
- safety escalation points to `AdminContact`
- fixture-only surfaces must remain labeled as designed/not live

## User Journey

### What Exists Now

The user is the non-technical recipient of the system. In `SOUL.md`, this is
Bob: change-averse, safety-sensitive, and not a reliable actor for IT or
release decisions.

Relevant shipped/designed surfaces include:

- tray/status rendering from CLI truth
- first-run wizard DTOs and frontend contracts in `src/types.ts`
- Bob prompt/notice contracts in `src/types.ts`
- routing rules that keep IT/release decisions away from Bob
- managed silent path design through forced `.mobileconfig` keys

The user experience target is:

- one double-click for unmanaged users, or zero-click managed install
- honest status
- sign-in only when needed
- personal dirty-work decisions only when genuinely user-owned
- no raw Git/VCS errors
- no release, MDM, or IT decisions pushed to the user

### Immediate Next Work

After Publisher and Admin have a real artifact/profile path, validate the
actual user first run.

Test both lanes:

1. **Managed user:** profile is already installed, wizard should be silent or
   minimal, Control Tower starts at login, and the tray reflects CLI truth.
2. **Unmanaged user:** first-run wizard asks only what the user can answer and
   never exposes org deployment concerns.

Acceptance target:

- A user can reach a working state without opening Terminal.
- Missing org/admin configuration routes to Admin, not User.
- Missing release trust routes to Publisher/Admin, not User.
- User-facing copy never exposes raw command output unless it is genuinely the
  user's own recoverable action.

### What Comes After That

Once managed and unmanaged first-run work on real machines:

1. Exercise updates from the publisher-produced artifact.
2. Confirm crash/watchdog behavior on a real install.
3. Confirm safety escalation reaches AdminContact without requiring user
   action.
4. Confirm user prompts remain limited to sign-in and dirty personal work.
5. Run a removal/deprovision scenario and verify user data boundaries.

The final user success signal is not "the app installed." It is: the user has
the Copilot ecosystem ready and self-healing without needing to understand the
release chain, MDM profile, Git, YAML, or terminal commands.

## Recommended Next Developer Sequence

1. Finish the uncommitted publisher app-run publishing flow.
2. Commit it after a real end-to-end artifact run or a documented blocker.
3. Update `docs/reference/publisher-admin-experience.md` so Publisher step 7
   says the app runs publishing directly, not "run commands."
4. Start Admin with profile/preflight, not fleet dashboard polish.
5. Use a real MDM-enrolled test Mac as soon as profile generation exists.
6. Only after Admin can deploy, validate the User first-run and tray flows.

## Known Risks

- The publisher app currently assumes fixed artifact paths. Tauri may emit a
  versioned DMG name; verify before relying on the Admin handoff screen.
- Admin mode has a strong design, but much of the standup path is still
  designed/not built.
- Fleet dashboard is fixture-backed; do not treat it as live observability.
- Two-of-N signing custody is not production-ready.
- No real IT operator has validated Admin mode yet. Keep the hypothesis label
  until one has.

## Definition Of Done For The Whole Chain

Publisher done:

- signed, notarized, stapled `.app`/`.dmg` exists
- publishing log is copyable
- no Developer ID or notarization secret leaves publisher custody

Admin done:

- artifact plus generated profile can be deployed to a managed test Mac
- preflight explains every blocker
- fleet status reflects real machines
- safety escalation reaches `AdminContact`

User done:

- managed user gets a ready system with no terminal work
- unmanaged user gets a clear first-run wizard
- app never asks the user to judge Publisher/Admin decisions
- status remains honest and recoverable
