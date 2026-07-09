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
| **Control Tower (Admin mode)** | A mode *inside* the shipped Tauri binary. | Org standup / config |
| **Control Tower (first-run wizard / tray)** | The *same* Tauri binary, user-facing. | Personal data + sign-in only |

The real design target is **no dead-ends in any of the three**: no unguided
Terminal, no hand-edited YAML, no undocumented "go ask someone," no cross-role
decision leak. Some steps *categorically cannot* be automated (creating an Apple
account, standing up a GitHub org, a key-custody ceremony).
For those the target is **guided teach-and-verify**, not automation. Conflating
"must be guided" with "must be automated" is the failure mode to avoid.

Jobs-to-be-done, per role:

- **Publisher:** *"Someone handed me a project I've never seen and told me to
  ship it. Walk me from 'I have nothing' to 'a signed artifact exists' without
  guessing which Apple credential does what, and never make me a shell user."*
- **Admin:** *"I'm told to stand up this org's Copilot Solutioning Ecosystem.
  Tell me exactly which GitHub repos to create, who to ask for which grant, how
  to wire the shared secret store, and the owner of every red item, so I stand
  up the org from a guided tool + docs and never hand-edit YAML."*
  (This is the literal SOUL success signal, SOUL §8.)
- **User (Bob):** *"When this lands on my Mac, give me a working partner from one
  double-click, let me join my own department without asking anyone, and ask me
  only about my own data, never a release or org-config decision I can't
  judge."*

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

Note (D10): a product/project the org builds with the CSE is not a fifth tier
here. It has its own repo and is standardized by the Copilot instruction layer
(Claude/Codex Copilot) when someone works in it. These four tiers are
**components** (Knowledge/CLI/Claude/Codex Copilot), never projects.

### 2b. Admin end-to-end sequence

Center of gravity (D3/D4): stand up the 4-tier component repos, grant team
access (entitlement), configure the central shared secret store, and author the
ecosystem seed. No MDM, no fleet console, no forced-key domain.

| # | Stage | Step | External party / grant | Build state |
|---|---|---|---|---|
| A0 | Orient + authority | Confirm org/config authority; get a GitHub org-owner sponsor + an `AdminContact` for safety escalation | GitHub org owner; `AdminContact` | N/A |
| A1 | Stand up repos | Create `copilot-org` + `copilot-dept-<unit>` per department; set org base-read | GitHub org owner | Design (docs only) |
| A2 | Grant team access (entitlement) | Create dept teams; grant read/write; this **is** the entitlement (D3: entitlement == repo access) | GitHub org owner / team-admin | Design; mechanism ratified |
| A3 | Provision authoring keys | Choose authors per dept; grant team write; provision each author's **own** on-device SSH key | Author + team-admin | Design |
| A4 | Configure central shared secret store | Deploy Infisical/OpenBao; scope access by GitHub-team membership; endpoint delivered via inherited org repo config, never MDM (D4/D6) | IT infra | Org decision, no code gap |
| A5 | Author the ecosystem seed | Generate `ecosystem.yml` (components/depts/pins/auth/policy_signers/telemetry) in-app, open the PR | N/A | **NOT BUILT** (interim: hand-author YAML) |
| A6 | Configure access policy signers | Sign the capability policy; set CODEOWNERS/rulesets on the executable paths | Policy signer | Design |
| A7 | Analytics opt-in (optional) | Off by default; only if org signs `telemetry.enabled/endpoint` | Org collector | Gate + transport seam built; real HTTP absent |
| A8 | Verify setup | Red/green: repos exist, seed parses, policy signed, secret store reachable, pins resolve; each red names its owner | N/A | **NOT BUILT** (interim: manual checklist) |
| A9 | Deprovision a leaver | Revoke the person's GitHub repo access + rotate shared-secret-store tokens (D4); no MDM, no remote wipe | GitHub org owner / secret-store admin | **NOT BUILT** (mechanism defined; no in-app action yet) |

Moments of truth: **A0** (every prerequisite is *another person*, highest
abandonment risk) and **A5** (forced back to hand-YAML, still the one place the
SOUL success signal is currently false).

Admin done = the four spine artifacts exist and verify clean: repos + teams
(entitlement), the central secret store, and a signed ecosystem seed; safety
escalation reaches `AdminContact`.

## 3. User (Bob) journey

Entry state: Bob hears about it once (a link to the signed `.dmg`), installs it
himself, and then hears nothing further unless something needs him. No MDM push
and no zero-touch (D4): one install path, not two lanes.

| # | Stage | What happens | Boundary rule |
|---|---|---|---|
| U0 | Arrival | Bob double-clicks the signed, notarized `.dmg` once | Never asked to install a profile or judge trust |
| U1 | First run | Wizard asks only what Bob can answer | Never exposes org/release concerns |
| U2 | Department discovery + join | Wizard/tray shows the departments Bob is entitled to, validated by his GitHub repo access; selecting one syncs that layer onto his machine (D7.1) | Bob only ever sees departments he's already entitled to; no admin decision leaks in |
| U3 | Personal sign-in | "Sign in to Slack" (his own account) → browser device-flow → token to OS keychain | Never sees a raw API key; this is *his* credential, never shared-store material |
| U4 | Entitled shared integrations | Org/dept integrations (Salesforce, Workday, Microsoft) already appear connected because his entitled layer provisions them from the central shared secret store; no sign-in prompt (D6/D7.2) | Shown as a distinct, separately-labeled register from U3; Bob never sets up a shared integration's credentials |
| U5 | Steady state | Tray parses `doctor --json`, worst-wins; silent when fine | Icon never fabricates Healthy |
| U6 | Cadence sync | Authorized upstream component change appears (foundation/org/dept); pull-only/downward | Never pushes personal content up |
| U7 | Personal-key multi-machine sync | Bob's own personal keys follow him to a second machine, ending the `.env` hand-copying (D7.3) | His keys, his machines only; never touches shared-store material |
| U8 | A change needs him | Only ever: his sign-in, his dirty personal WIP, or a new department to join | Held-major/policy/security → IT (`AdminContact`), never Bob |
| U9 | Conflict (author-Bob only) | Plain-language keep-yours/theirs/both/escalate | Raw Git never shown |
| U10 | Safety event | Auto-acted, past-tense ("kept you safe"); IT notified content-free | Bob never approves/unblocks |
| U11 | Update / rollback | Crash-only watchdog; bad update → "kept your working version" | Never a scary failure dialog |
| U12 | Departure | His GitHub repo access is revoked and shared-secret-store tokens rotated; already-synced content on his disk is not remotely wiped (accepted residual, D4) | Bob takes no action; revocation is server-side and he cannot reverse it |

The intended arc is deliberately **flat and quiet**: "it just sits there,
quietly solid" (SOUL §8). The only sanctioned peaks are U3 ("I just click sign-in
and it works") and U11 ("it kept my work when the update went bad"). Every
negative emotion Bob could feel is an anti-pattern the product exists to design
*out*.

User done = Bob gets a ready system with no terminal, joins his own department
without asking anyone, can tell his personal sign-ins apart from integrations
that were just there because he's entitled to them, and the app never asks him
to judge a Publisher/Admin decision; status stays honest and recoverable.

## 4. Dead-ends & gaps (the design targets)

| # | Role | Gap |
|---|---|---|
| G1 | Publisher | G1/G2 cert "untrusted" trap; naive "Always Trust" masks the real chain problem |
| G2 | Publisher | CSR/private-key mismatch → *silent* inability to sign |
| G3 | Publisher | Handoff contents under-specified (Team ID/version/compat assembled by hand) |
| G4 | Publisher | **DMG path assumption**: app assumed fixed name; Tauri emits versioned name (**FIXED** in redesign) |
| G5 | Publisher | CI + two-of-N custody undecided; update-feed URL still a placeholder |
| G6 | Admin | **`ecosystem.yml` seed generator NOT BUILT**: Admin must hand-author YAML |
| G7 | Admin | **Setup verification NOT BUILT**: no red/green check that repos, teams, the secret store, and the seed are correctly wired before Bob's first sync |
| G8 | Admin | GitHub topology is docs-only, not an in-app flow |
| G9 | Admin | "Who to talk to" is implicit prose, no contacts artifact |
| G10 | Admin | Analytics carrier field unratified |
| G11 | User | **Department discovery/join has no UI**: nothing surfaces which departments Bob is entitled to or lets him join by repo access (D7.1) |
| G12 | User | **Shared-vs-personal integration split doesn't exist**: the current model conflates personal sign-in (device-flow) with entitled shared integrations provisioned centrally (D7.2) |
| G13 | User | **Personal-key multi-machine sync unbuilt**: Bob still hand-copies `.env` between his own machines (D7.3) |
| G14 | Cross | Publisher→Admin→User is a sequential gate with no shared status object |

## 5. "Must be in the app" list

### 5a. Publisher Setup.app (repo-local SwiftUI): **redesigned in this pass**
Covered P0–P11. This pass **added/hardened**: a persistent roadmap sidebar; a
Welcome/orientation screen; a **cert-trust verify** screen closing G1/G2;
**dynamic DMG-path resolution** closing G4; a **structured Publisher→Admin
handoff** block closing G3 (feeds G14). P1/P3/P4/P6/P7 remain TEACH screens
(Apple's own web console, cannot/should not be automated). P12 (CI secrets) and
P13 (custody ceremony) stay owner-gated; the app names them as next steps.

### 5b. Control Tower (Admin mode, Tauri): the biggest build gap
1. Prerequisites & contacts screen (names the GitHub org owner + `AdminContact`, closes G9).
2. GitHub topology guide, teach + verify (closes G8).
3. "Who authors" decision flow + on-device SSH keygen (A3).
4. Central shared secret store setup guide: connect Infisical/OpenBao, scope by GitHub team (A4).
5. **Seed generator**: author `ecosystem.yml` in-app + open the PR (closes G6). Highest-value build.
6. Access policy signer flow: sign the capability policy, set CODEOWNERS/rulesets (A6).
7. Setup verification: red/green over repos, teams, secret store, and seed, each red names its owner (closes G7).
8. Guided deprovision action: revoke GitHub repo access + rotate shared-secret-store tokens.

### 5c. Control Tower (first-run wizard / tray, Tauri, user)
1. Single self-install first-run wizard asking only Bob-answerable things; honest holding states (never false-Healthy).
2. Department discovery + join: surface entitled departments, validate by GitHub repo access, sync on selection (closes G11).
3. Device-flow personal sign-in, rendered as a distinct register from entitled shared integrations (closes G12); native secure input for legacy key integrations.
4. Personal-key multi-machine sync surface (closes G13).
5. Plain-language conflict chooser (CLI-computed, app-rendered).
6. Hard boundary: held-major/policy/security/deprovision → IT via `AdminContact`, never Bob.

### 5d. Cross-cutting (closes G14)
A shared handoff status object in the CLI `--json` contract that each surface
renders: `{publisher: done|blocked, admin: done|blocked, artifact_ref,
next_owner}`. Belongs in the CLI per parse-never-compute; all three surfaces
render it.

## 6. Residual risk

The Admin journey is a **HYPOTHESIS**: no real IT operator has touched it
(`06-deployment/README.md` banner; SOUL §9 #9). Every Admin recommendation should
be prototyped with one real operator before it hardens; the seed generator (G6)
and setup verification (G7) are the two builds that most directly convert the
hypothesis into the ratified SOUL success signal.
