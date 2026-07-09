# Three-Role Journey Map: Publisher · Admin · User

Service-design review of the end-to-end onboarding experience for Copilot
Control Tower, grounded in the repo's own docs. Produced during the publisher
setup redesign; it is the foundation for the Admin and User work that follows.

Evidence base: `SOUL.md` · `CLAUDE.md` · `docs/HANDOFF-PUBLISHER-ADMIN-USER.md`
· `docs/reference/publisher-admin-experience.md` ·
`docs/07-contributing/publisher-release-runbook.md` ·
`docs/06-deployment/README.md` · `docs/06-deployment/standup-runbook.md` ·
`docs/08-observability/operator-guide.md` ·
`docs/01-architecture/inheritance-and-publish.md` ·
`docs/05-security/credentials-and-boundary.md` ·
`docs/reference/four-tier-topology.md` · `scripts/publisher_setup.swift`.

## 0. Reframe: there is no single "the app"

The brief "everything should happen within the app" silently collapses **three
different binaries with three different authorities**, and the product's own
invariants (SOUL §9 role split; `publisher-release-runbook.md` §"Repo boundary")
*forbid* merging them:

| Surface | What it actually is | Authority |
|---|---|---|
| **Publisher Setup.app** | Repo-local SwiftUI utility (`scripts/publisher_setup.swift`). Not the product binary, not a customer feature. | Release-signing only |
| **Control Tower (Admin mode)** | A mode *inside* the shipped Tauri binary. | Fleet / config |
| **Control Tower (first-run wizard / tray)** | The *same* Tauri binary, user-facing. | Personal data + sign-in only |

The real design target is **no dead-ends in any of the three**: no unguided
Terminal, no hand-edited YAML, no undocumented "go ask someone," no cross-role
decision leak. Some steps *categorically cannot* be automated (creating an Apple
account, clicking in Jamf, standing up a GitHub org, a key-custody ceremony).
For those the target is **guided teach-and-verify**, not automation. Conflating
"must be guided" with "must be automated" is the failure mode to avoid.

Jobs-to-be-done, per role:

- **Publisher:** *"Someone handed me a project I've never seen and told me to
  ship it. Walk me from 'I have nothing' to 'a signed artifact exists' without
  guessing which Apple credential does what, and never make me a shell user."*
- **Admin:** *"I'm told to deploy this fleet-wide. Tell me exactly which GitHub
  repos to create, who to ask for which grant, and the owner of every red item,
  so I stand up the org from a guided tool + docs and never hand-edit YAML."*
  (This is the literal SOUL success signal, SOUL §8.)
- **User (Bob):** *"When this lands on my Mac, give me a working partner from one
  double-click or zero, and ask me only about my own data, never a release or
  MDM decision I can't judge."*

## 1. Publisher journey

Entry state: *"I've never heard of this. Someone sent me the repo and approved me
to ship it."*

Legend for **App:** `AUTO` = setup app performs it · `TEACH` = app explains +
links, human acts externally · `VERIFY` = app detects/confirms result ·
`N/A` = outside the app entirely.

| # | Stage | Step | Prerequisite / credential | External party | Artifact | App |
|---|---|---|---|---|---|---|
| P0 | Orient | Understand publisher = *signing* authority only | none | Whoever sent the repo | Mental model | TEACH |
| P1 | Apple membership | Join/confirm Apple Developer Program; find Team ID | Apple ID, $99/yr | **Apple** | Membership, Team ID | TEACH + VERIFY |
| P2 | CSR | Keychain Access → request cert from a CA; save `.certSigningRequest` | login keychain w/ private key | none | `.certSigningRequest` | TEACH |
| P3 | Developer ID cert | Create Developer ID Application cert (G2 Sub-CA), upload CSR, install `.cer` | P1, P2 | **Apple** | Cert in login keychain | TEACH |
| P4 | Intermediate | If untrusted, install Developer ID G2 intermediate; leave trust at System Defaults (never "Always Trust") | P3 | Apple PKI | Trusted chain | TEACH |
| P5 | Private-key check | Confirm private key under cert; `security find-identity -v -p codesigning` | P3 on the CSR Mac | none | Verified identity string | AUTO detect + VERIFY |
| P6 | Notary Apple ID | Know which Apple ID owns notarization for this Team ID | P1 | Apple | (knowledge) | TEACH |
| P7 | App-specific password | `account.apple.com` → App-Specific Passwords → generate | P6 | **Apple** | App-specific password (transient) | TEACH |
| P8 | Store notary profile | `xcrun notarytool store-credentials` (no password as arg) | P5, P7 | none | Keychain profile | **AUTO** |
| P9 | Release env | Write `.env.release.local` (mode 600, gitignored) | P8 | none | `.env.release.local` | **AUTO** |
| P10 | Build/sign/notarize/staple | One click → live progress + copyable log | P9, toolchain | none | Signed/notarized `.app` + `.dmg` | **AUTO** |
| P11 | Handoff to Admin | Success screen names artifact + Team ID + version + update-signing status | P10 | The Admin | Handoff block | AUTO |
| P12 | CI promotion (later) | Move proven path to CI using App Store Connect **API-key** secrets | P10 proven locally | GitHub repo admin | CI release env | N/A (owner-gated) |
| P13 | Stable self-update custody | Assign two-of-N minisign custody + real update-feed URL | production decision | Second key-holder | Signed `latest.json` roots | N/A (owner-gated) |

Moments of truth: **P3–P4** (the G2-cert "untrusted / Always-Trust" trap, the
single most likely stranding point) and **P10** (one button vs. copy-pasting
terminal commands, where the no-dead-end promise is won).

Publisher done = signed/notarized/stapled `.app`/`.dmg` exists; log is copyable;
no Developer ID / notarization secret ever left publisher custody.

## 2. Admin journey

Entry state: *"Never heard of this; told to make sure it's set up correctly across
the org."* Starts **only after** a signed artifact exists (P11).

### 2a. GitHub repo topology the Admin must stand up

Precedence **PERSONAL › DEPARTMENT › ORG › FOUNDATION**; four tiers across three
namespaces. Option A (separate repo per department) is the ratified default:
department content is confidential and GitHub's only read boundary is the repo
(`four-tier-topology.md` §2, §6.2).

| Tier | Repo(s) | Namespace | Who creates / grants |
|---|---|---|---|
| Foundation | `Everyone-Needs-A-Copilot/claude-copilot` (public) | ENAC public | Exists; anon HTTPS pull, no grant |
| Org | `<org>/copilot-org` | Enterprise org | GitHub org owner creates; org base permission = **read** |
| Department | `<org>/copilot-dept-<unit>` (per dept) | Enterprise org | Org owner creates repo; a `<org>/<unit>` team granted read/write |
| Personal | `github.com/<user>/claude-copilot-private` | User's personal acct | The user; write via their **own** on-device SSH key |

Multi-account auth standard: SSH host aliases `github-personal` / `github-work`
with `IdentitiesOnly yes`, the only mechanism that disambiguates two
`github.com` identities on one machine (`four-tier-topology.md` §6.1).

### 2b. Admin end-to-end sequence

| # | Stage | Step | External party / grant | Build state |
|---|---|---|---|---|
| A0 | Orient + authority | Confirm fleet/config authority; get MDM console + GitHub org-admin sponsor | GitHub org owner; MDM admin; an `AdminContact` | N/A |
| A1 | Stand up repos | Create `copilot-org` + `copilot-dept-<unit>`; set org base-read; create dept teams | GitHub org owner | Design (docs only) |
| A2 | Decide who authors | Choose authors per dept; grant team write; provision their **own** on-device SSH key | Author + team-admin | Design; mechanism ratified |
| A3 | Author `ecosystem.yml` seed | Generate the seed (products/depts/pins/auth/policy_signers/telemetry) | N/A | **NOT BUILT** (interim: hand-author YAML) |
| A4 | Configure access + policy signers | Sign capability policy; set CODEOWNERS/rulesets on executable paths | Policy signer | Design |
| A5 | Gather managed keys | Collect the 17 forced-domain keys (`OrgSlug`, `EcosystemSeedURL`, `AdminContact`, `UpdateFeedURL`, `DisableWizard`, …) | Org decisions | Registry shipped; **collection UI not built** |
| A6 | Generate `.mobileconfig` | Run generator → one profile w/ prefs + login-item + notifications; fail-closed secret scan | N/A | **SHIPPED (M5)**: the one step real today |
| A7 | Preflight | Red/green: seed parses, dept repos exist, policy signed, profile complete, pin resolves, mirror reachable; each red names its owner | N/A | **NOT BUILT** (interim: manual checklist) |
| A8 | Upload to MDM | Upload `.mobileconfig` + artifact to Jamf/Kandji/Intune; scope to group | MDM console | Artifact real; per-MDM path unwritten; forced-key-takes-effect unverified |
| A9 | Login-item + safety channel | Login-item rides the profile; set **mandatory** `AdminContact` | IT monitored endpoint | **SHIPPED (M5)**; unverified on real Mac |
| A10 | Analytics opt-in (optional) | Off by default; only if org signs `telemetry.enabled/endpoint` | Org collector | Gate + transport seam built; real HTTP absent |
| A11 | Shared secret store (optional) | Deploy Infisical/OpenBao; scope by GitHub-team; deliver URL via MDM only | IT infra | Org decision, no code gap |
| A12 | Roll out to test Mac | Push build via MDM; first run reads forced keys; wizard silent if `DisableWizard` | MDM | Design |
| A13 | Verify fleet | Per-host worst-wins + safety feed; **no fleet-health score exists** | N/A | Frontend renders **fixtures only**; no live backend |
| A14 | Deprovision a leaver | Set forced `Deprovisioned=true` (never mere profile removal) | MDM | **SHIPPED (M5)**; unverified on real Mac |

Moments of truth: **A0** (every prerequisite is *another person*, highest
abandonment risk) and **A3** (forced back to hand-YAML, the one place the SOUL
success signal is currently false).

Admin done = artifact + generated profile deploy to a managed test Mac; preflight
explains every blocker; fleet reflects real machines; safety escalation reaches
`AdminContact`.

## 3. User (Bob) journey

Entry state: Bob does nothing and heard nothing, by design. Two lanes.

| # | Stage | Managed (MDM) lane | Unmanaged lane | Boundary rule |
|---|---|---|---|---|
| U0 | Arrival | App + profile pushed silently; starts at login | Bob double-clicks the `.dmg` once | Never asked to install a profile or judge trust |
| U1 | First run | `DisableWizard` forced → zero-question silent provision | Wizard asks only what Bob can answer | Never exposes org/MDM/release concerns |
| U2 | Integration sign-in | "Sign in to Slack" → browser device-flow → token to OS keychain | Same | Never sees a raw API key |
| U3 | Steady state | Tray parses `doctor --json`, worst-wins; silent when fine | Same | Icon never fabricates Healthy |
| U4 | Cadence sync | Authorized upstream change appears; pull-only/downward | Same | Never pushes personal content up |
| U5 | A change needs him | Only ever: his sign-in, or his dirty personal WIP | Same | Held-major/policy/security → IT, never Bob |
| U6 | Conflict (author-Bob only) | Plain-language keep-yours/theirs/both/escalate | Same | Raw Git never shown |
| U7 | Safety event | Auto-acted, past-tense ("kept you safe"); IT notified content-free | In-app only | Bob never approves/unblocks |
| U8 | Update / rollback | Crash-only watchdog; bad update → "kept your working version" | Same | Never a scary failure dialog |
| U9 | Departure | Forced `Deprovisioned=true` wipes/quarantines | n/a | Bob takes no action |

The intended arc is deliberately **flat and quiet**: "it just sits there,
quietly solid" (SOUL §8). The only sanctioned peaks are U2 ("I just click sign-in
and it works") and U8 ("it kept my work when the update went bad"). Every negative
emotion Bob could feel is an anti-pattern the product exists to design *out*.

User done = managed user gets a ready system with no terminal; unmanaged gets a
clear wizard; the app never asks the user to judge Publisher/Admin decisions;
status stays honest and recoverable.

## 4. Dead-ends & gaps (the design targets)

| # | Role | Gap |
|---|---|---|
| G1 | Publisher | G1/G2 cert "untrusted" trap; naive "Always Trust" masks the real chain problem |
| G2 | Publisher | CSR/private-key mismatch → *silent* inability to sign |
| G3 | Publisher | Handoff contents under-specified (Team ID/version/compat assembled by hand) |
| G4 | Publisher | **DMG path assumption**: app assumed fixed name; Tauri emits versioned name (**FIXED** in redesign) |
| G5 | Publisher | CI + two-of-N custody undecided; update-feed URL still a placeholder |
| G6 | Admin | **`ecosystem.yml` seed generator NOT BUILT**: Admin must hand-author YAML |
| G7 | Admin | **Preflight NOT BUILT**: no red/green safety net before a fleet push |
| G8 | Admin | Managed-key collection has no UI (17 keys exist in `keys.rs`, nothing gathers them) |
| G9 | Admin | No per-MDM (Jamf/Kandji/Intune) walkthrough; forced-key-takes-effect unverified |
| G10 | Admin | GitHub topology is docs-only, not an in-app flow |
| G11 | Admin | "Who to talk to" is implicit prose, no contacts artifact |
| G12 | Admin | Fleet dashboard fixtures-only; no live backend |
| G13 | Admin | Analytics carrier field unratified |
| G14 | User | Managed vs unmanaged first-run unproven on real machines |
| G15 | Cross | Publisher→Admin→User is a sequential gate with no shared status object |

## 5. "Must be in the app" list

### 5a. Publisher Setup.app (repo-local SwiftUI): **redesigned in this pass**
Covered P0–P11. This pass **added/hardened**: a persistent roadmap sidebar; a
Welcome/orientation screen; a **cert-trust verify** screen closing G1/G2;
**dynamic DMG-path resolution** closing G4; a **structured Publisher→Admin
handoff** block closing G3 (feeds G15). P1/P3/P4/P6/P7 remain TEACH screens
(Apple's own web console, cannot/should not be automated). P12 (CI secrets) and
P13 (custody ceremony) stay owner-gated; the app names them as next steps.

### 5b. Control Tower (Admin mode, Tauri): the biggest build gap
1. Prerequisites & contacts screen (names the four external parties, closes G11).
2. GitHub topology guide, teach + verify (closes G10).
3. "Who authors" decision flow + on-device SSH keygen (A2).
4. **Seed generator**: author `ecosystem.yml` in-app + open the PR (closes G6). Highest-value build.
5. Managed-key collector + validator over the 17 keys (closes G8).
6. Preflight red/green, each red item names its owner (closes G7).
7. Per-MDM upload walkthroughs + "confirm forced key flipped" verify (closes G9).
8. Honest fleet view: per-host worst-wins, no health score, wire the live backend (closes G12).
9. Guided deprovision action.

### 5c. Control Tower (first-run wizard / tray, Tauri, user)
1. Silent managed first-run + honest holding states (never false-Healthy).
2. Unmanaged wizard asking only Bob-answerable things.
3. Device-flow sign-in rendering; native secure input for legacy key integrations.
4. Plain-language conflict chooser (CLI-computed, app-rendered).
5. Hard boundary: held-major/policy/security/deprovision → IT via `AdminContact`, never Bob.

### 5d. Cross-cutting (closes G15)
A shared handoff status object in the CLI `--json` contract that each surface
renders: `{publisher: done|blocked, admin: done|blocked, artifact_ref,
next_owner}`. Belongs in the CLI per parse-never-compute; all three surfaces
render it.

## 6. Residual risk

The Admin journey is a **HYPOTHESIS**: no real IT operator has touched it
(`06-deployment/README.md` banner; SOUL §9 #9). Every Admin recommendation should
be prototyped with one real operator before it hardens; the seed generator (G6)
and preflight (G7) are the two builds that most directly convert the hypothesis
into the ratified SOUL success signal.
