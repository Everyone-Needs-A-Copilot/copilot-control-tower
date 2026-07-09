# Copilot Control Tower — Native macOS Experience Architecture

Stage 1 of 3 of the native-app redesign (this = structure / IA / state inventory;
uxd = interaction; uids = visual system). Grounded in the **corrected CSE model**
(`docs/reference/copilot-solutioning-ecosystem.md`), the alignment decisions
(`docs/reference/cse-alignment-decisions.md`, D1–D10), the conformed
`docs/03-design/three-role-journeys.md`, `docs/05-security/credentials-and-boundary.md`,
`docs/01-architecture/cli-contract.md` (the new `copilot layers`/`layers join`
verbs), and the closed sets in `src/types.ts`. No visual/pixel design here.

Decision context: an earlier native-architecture pass was built on a **wrong
domain model** — it treated Control Tower as syncing a *catalog of products* and
carried a pervasive MDM/fleet framing. Both are now corrected. This document
**reuses the prior pass's craft** (the native-container surface map, the
"Quiet Instrument" quality system, honest-degrade, shape-first badges) and
**replaces its domain**. The Tauri-web UI the owner rejected is out; the target
is a true native macOS SwiftUI/AppKit app (menu-bar tray + windows), macOS-only,
shelling out to the CLI and rendering its `--json` truth (invariant #1,
parse-never-compute). The "Tauri v2 / Windows re-skin" line in `CLAUDE.md` is
deliberately overridden for this native rebuild.

## 0. Reframe: what Control Tower actually shows, and the three authorities

**The load-bearing correction (D1, D2, D8, D10).** Control Tower keeps a user's
machine current with the **CSE tooling components** — the Claude/Codex Copilot
instruction layer, Knowledge Copilot (knowledge layer), and CLI Copilot
(integration layer) — across the **four inheritance layers** they are
**entitled** to (`foundation -> org -> department -> personal`). It does **not**
show, list, or sync the **products/projects** you build *with* that tooling
(Insights Copilot, Pipeline, Method are outputs — never a Control Tower surface,
D8/D10). Everywhere the prior pass said "product," read **component**; the word
"product" never surfaces in user copy again.

- **Entitlement is GitHub repo access (D3).** A user has a layer iff they can
  read that layer's repo. Discovery and join are computed CLI-side
  (`copilot layers` / `copilot layers join`, D7.1) and rendered by the app.
- **MDM is dropped completely (D4).** No `.mobileconfig`, no managed/forced
  config domain, no fleet-dashboard-as-center, no managed-key collector, no
  two-lane install. **One install path:** the user self-installs the signed,
  notarized `.dmg`. Security-sensitive config is now honored from compiled-in
  trust roots + signed inherited org/foundation config, never local user config.
- **Projects are self-contained (D10).** A project carries its own knowledge /
  skills / agents / integrations inside its own repo, materialized by the
  instruction layer when you work in it — it is **not** a Control Tower layer.
  There is no "project" surface (the removed `DeptProjectView`, D8).

Three authorities stay **structurally** separated, each on the right native
container (SOUL §9; invariant #5):

| Surface | What it is | Authority |
|---|---|---|
| **Publisher Setup.app** | A separate native SwiftUI binary (`scripts/publisher_setup.swift`, redesigned per `publisher-setup-visual-spec.md`). Not the product binary. | Release-signing only |
| **Control Tower — Admin mode** | A capability-gated mode *inside* the shipped app. Stands up the org's CSE via GitHub (repos / teams / secret store / seed). | Org standup + governance |
| **Control Tower — user face (tray + wizard)** | The same shipped app, user-facing. Component currency, department join, personal data, personal sign-in only. | Personal data + entitlement only |

The user must be **structurally unable** to reach Admin — the boundary is a
capability gate, not a tab a curious user can click.

## 1. Surface architecture (native containers + HIG justification)

Reused surfaces keep their prior numbering; **S2b is removed** (no managed-silent
first run, D4); **S11–S13 are new** for the three CSE gaps (D7).

| # | Surface | Native container | Why |
|---|---------|------------------|-----|
| S1 | Menu-bar presence | `NSStatusItem` template glyph (aviator, `#2D294E` **monochrome tint only**) + transient anchored `NSPopover` as the day-to-day home; right-click = minimal `NSMenu` (About, Preferences…, Quit) | Correct home for an always-on background utility with no Dock presence; a popover renders honest component-currency a menu cannot. **Reused unchanged.** |
| S2 | First-run wizard (**the only install path**) | Standalone titled window, `.contentSize`, centered; survives focus loss during browser sign-in | HIG treats setup assistants as windows; a menu-bar app has no host window for a first-run sheet. D4 collapses the old managed/unmanaged two-lane to this one guided window. |
| ~~S2b~~ | ~~First-run (managed silent)~~ | **REMOVED (D4)** | No MDM `DisableWizard`; there is no silent lane to render. `WizardMode.managed` in `types.ts` is now a vestigial arm (see §6). |
| S3 | Settings | Native `Settings` scene (`⌘,`), tabbed: General · Components & Layers · Integrations · Personal Key Sync · Advanced · (conditional) Administration | Standard Preferences home; the tabs carry the corrected domain (entitled layers + join, the shared/personal integration split, personal-key sync). |
| S4 | Admin mode | Distinct `Window` scene, own toolbar + navigation sidebar, entered only via a capability-gated entry point | Org standup is a substantial multi-step tool of a different authority; must not share a window with user status. Sections are **Onboarding + Governance** — no fleet-as-center (D4). |
| S5 | **Personal** sign-in device-flow | Dedicated non-transient panel (sheet on the wizard; standalone panel from steady state), NOT the popover | A popover auto-dismisses on focus loss; device-flow requires leaving for Safari; the 8-char code must stay visible. Carries only `user_code`/`verification_uri`, **never a token** (`SigninState`). This is the **personal** register only — shared integrations never use it (S12). |
| S6 | Dirty-work prompt | `UNNotification` → small panel; never the popover | One of the two sanctioned Bob interruptions (`BobPrompt.dirty-wip`); must persist. If notifications denied, re-host in popover with an honest "why here" note (`notifications_denied`). |
| S7 | Conflict chooser (author only) | Modal sheet rendering CLI-computed options | keep-yours/theirs/both/escalate are CLI-computed (`copilot publish`); app renders + returns the choice; never raw Git markers. |
| S8 | Deprovision | Render-only; to the user a quiet notice, to IT a `DeprovisionView` panel in Admin › Governance | A render of a **GitHub-access-revocation + secret-store-token-rotation** event (D4 — no MDM wipe), never UI-triggered. `retained_dirty` prominent, `secrets_alarm` honest. |
| S9 | Update / rollback | Popover progress + past-tense notice; never a modal alert | Self-update transport only; a bad update surfaces as "Kept your working version." |
| S10 | About | Standard About window | Carries the product name; "Aviator" banned from user surfaces. |
| **S11** | **Department discovery + join** *(new, load-bearing, D7.1)* | A section in the wizard **and** a standing panel (Settings › Components & Layers; reachable from the popover's "Join available" row) rendering `copilot layers --json`; join fires `copilot layers join <id>` | The single biggest CSE gap the prior pass descoped. Entitlement is CLI-computed; the app only renders the entitled/joined list and passes the pick back (invariant #1). Not a modal — it is a durable, revisitable surface because entitlement changes over time. |
| **S12** | **Entitled shared-integrations register** *(new, D6/D7.2)* | A **read-only** list, a distinct region in the popover and Settings › Integrations, visibly separate from S5 | Org/dept integrations (Salesforce, Workday, Microsoft) are provisioned centrally by entitlement via the shared secret store; the user **does not authenticate** them. Rendered as "available because you're entitled," with **no** sign-in affordance — the exact opposite register from S5's device-flow. Conflating the two was a prior-domain error (D7.2). |
| **S13** | **Personal-key multi-machine sync** *(new, D7.3)* | A section in Settings › Personal Key Sync | Ends the `.env` hand-copying between a user's own machines. His keys, his machines only; never shared-store material, never git. Mechanism open (§6); the surface is designed now. |

Deliberately **NOT** a surface: any product/output catalog; any chat box; any
"make it healthy" override; any MDM/`.mobileconfig`/managed-key screen; any
control that re-points `UpdateFeedURL`/mirror/secret-store endpoint from user
config (honored only from signed inherited org config).

## 2. Information architecture & navigation

**Three concentric worlds, on the corrected domain:**

1. **The glyph** (everyone, always) — one honest worst-wins state across the
   user's **component × entitled-layer** currency; silence = fine.
2. **The popover** (the user's home) — status sentence + the **component ×
   entitled-layer currency tree** + the **entitled-not-synced "Join available"**
   affordance + a small action set + the two integration registers (S12 shared,
   S5 personal) clearly separated + the Bob lane.
3. **Settings and Admin** (windows launched from the popover/menu, never nested).

**The department-join flow (S11) lives in two places, one mechanism.** At first
run it is a wizard step; in steady state it is a standing Settings panel and a
popover "Join available" row that appears only when `copilot layers` reports an
entitled, not-yet-joined layer. Both render the identical `layers` list and both
fire `layers join`. Bob only ever sees departments he is *already entitled to* —
no admin decision leaks into his surface.

**The shared-vs-personal integration split is structural in the IA, not just
visual.** Two registers that never merge:
- **Shared (S12):** entitled, centrally provisioned, read-only, *no sign-in*.
- **Personal (S5):** device-flow sign-in, *his* credential, per-person.
They render as two separately-labeled regions so Bob can always tell "just there
because I'm entitled" from "I signed in myself."

**The user never navigates upward into Admin.** The Admin entry point (the
Administration Settings tab and any "Open Administration…" item) is **absent, not
disabled**, unless an `admin_capable` fact is true. Per the earlier decision (D4
context), `admin_capable` is a **first-run opt-in** on an unmanaged machine ("I'm
setting this up for my org") — there is no MDM forced-domain grant path anymore.
Hiding (not disabling) is correct because exposure itself is the harm — distinct
from the honest "show the slot, disabled" convention used for un-granted
components and entitled-not-synced rows, where visibility is honest information,
not a competence leak.

**Admin mode is one window with a left navigation sidebar in two sections:**
**Onboarding** (do-once standup checklist) and **Governance** (occasional). The
onboarding header carries the shared handoff status object
`{publisher, admin, artifact_ref, next_owner}` so the Admin always sees where the
baton is. **There is no "Fleet" section as a center of gravity (D4)** — see §3.H.

## 3. Complete screen & state inventory (by role, on the corrected domain)

### 3.A User tray glyph — 12 badge tokens (shape-first, color-stripped legible)

The closed `BadgeState` set (`src/types.ts`, cross-checked against Rust
`render::BADGE_VOCABULARY`), reused **verbatim** — no new tokens:

`none` (fine, silence) · `hollow`/pulse (setup-needed — **also the honest shape
for an entitled-not-synced layer when the machine has no joined layers yet**) ·
`wrench` (it-config-incomplete) · `clock` (waiting-for-network) · `cloud-slash`
(offline) · `ring` (syncing) · `key` (signed-out — **personal** sign-in only) ·
`update` (update-available) · `triangle` (needs-attention) · `spinner`
(updating-app) · `bang` (the only red "!" — cli-unreadable / honest "versions
don't match, I won't guess"; the exact state the owner saw — honest-degrade, not
a bug) · `pass` (row-level dot only, never the tray).

The glyph is **worst-wins across the user's component × entitled-layer
currency**, computed CLI-side (`HeaderView.glyph_state`) — the app adds no
verdict. An entitled-not-synced department does **not** nag the tray: it renders
as a quiet popover "Join available" affordance (§3.B), and only raises the glyph
to setup-needed (`hollow`) when the machine genuinely has no joined layers yet.

### 3.B User popover states

The header is the one honest status sentence + glyph (`HeaderView`, never
fabricated). Body states:

- **Component × entitled-layer currency tree.** The `products[]` DTO
  (`ProductView`, field rename `product -> component` pending D2 — see §6) is
  **the component-currency view**: one row per CSE component (Knowledge / CLI /
  Claude / Codex Copilot), each with its four `LayerView` cells
  (`foundation | org | dept | personal`) carrying `severity` + `badge_state`.
  **This is the corrected core:** components across entitled layers — never a
  product list. A layer the user is **not** entitled to renders as an honest
  empty/`none` slot (shown, not hidden), not a fabricated pass.
- **Entitled-not-synced "Join available" row** *(new)*. When `copilot layers`
  reports `entitled: true, joined: false`, the popover shows a quiet, plain
  affordance ("Your Sales department is available to join") with a **Join**
  action → `copilot layers join`. Rendered honestly as `hollow` (setup-needed
  shape), never as healthy, never as an alarm.
- **Two integration registers, separated.** A **Shared** region (S12): entitled
  integrations, read-only, "available because you're entitled," no sign-in. A
  **Personal** region: `signed-out` rows offer "Sign in to Slack" → S5.
- **Steady states** (from `CliStatus` + the app-owned 11th): Healthy · setup-needed
  · it-config-incomplete · waiting-for-network · offline · syncing · signed-out ·
  update-available · needs-attention · updating-app · cli-unreadable ·
  notifications-denied fallback.
- **Bob lane** — closed sets, authoritative, nothing invented: prompts
  `sign-in | dirty-wip` (the only two, `BobPromptKind`); notices
  `kept-you-safe | kept-your-working-version | waiting-on-it` (`BobNoticeKind`);
  security banner un-dismissable, `reaffirm` only (`SecurityBanner`). Any
  held-major / policy / security / deprovision event routes to IT via `ItSignal`,
  **never** a new Bob prompt.

### 3.C User wizard (one guided path, D4)

No managed-silent lane. One window; never fabricates Healthy. Phase machine
(`WizardPhaseTag`): **Welcome → Detect → Choose components → Personal layer setup
→ Department discovery/join → Personal sign-in → Materialize → Verify → Teach →
Done**, with **Holding** as the honest terminal (plain reason in
`WizardState.error`).

- **Choose components** (`WizardStepKind: choose-products`, DTO name pending D2):
  "Which copilots do you want set up?" — the CSE **components**, never products.
  Ungranted ids render visible-but-disabled (honest slot).
- **Personal layer setup** (`layer-setup`): personal-tier repo-URL rows only —
  this is the user's *own* layer, always personal-tier, always editable
  (`WizardLayerSlot`). Org/dept authoring is not here (Settings/Admin).
- **Department discovery/join** *(new step, S11)*: renders `copilot layers` —
  the departments Bob is entitled to; joining fires `copilot layers join`. This
  is distinct from personal layer setup (his own repo) — it is *inheriting an
  entitled shared layer*. (Note: `types.ts` flags that the landed Rust
  `set_layers` has no company/department arg; this step is backed by the new
  `layers` verbs, not `set_layers` — a clean seam, not the old descoped Q3.)
- **Personal sign-in** (S5): device-flow, `SigninState` only, no token on the
  surface. **Shared integrations are never a wizard step** — they simply appear
  connected in S12 because the joined layer provisioned them (D6).
- **Materialize**: a named phase, no ETA/countdown (`phase_label` is a name,
  never a percentage). **Verify**: Healthy only reaches Done (icon-can't-lie).

### 3.D–F Personal sign-in panel, conflict chooser, update/rollback

- **Sign-in (S5, personal only):** `idle|pending|authorized|denied|expired|timeout`
  (`SigninStatus`); `signin_interval_secs` is polling bookkeeping, **never** a
  rendered countdown; no token on this surface, ever.
- **Conflict (author only, S7):** auto-merged (invisible) / keep-yours /
  keep-theirs / keep-both (the lossless floor) / park-and-escalate; CLI-computed
  via `copilot publish`; the app renders content-level versions, never `<<<<<<<`.
- **Update (S9):** `idle|checking|up-to-date|available|downloading|verifying|
  staging|ready|rolled-back|error` (`UpdateStatus`); idle/up-to-date render
  nothing; rolled-back → "Kept your working version"; error → plain `message`,
  never raw signature/watchdog text. This is the app's own transport, distinct
  from the CLI's `update-available` component verdict.

### 3.G Settings (S3) — tabbed, corrected domain

- **General:** surfaces login-item state (does not re-point it); About link.
- **Components & Layers:** the entitled-layer view — one row per component ×
  layer with currency, **plus the standing Department discovery/join panel (S11)**
  rendering `copilot layers` (entitled/joined) with Join actions. Managed org/dept
  rows are shown locked ("managed by your org"); personal rows are editable
  (`LayerRow.editable`). Errors are plain language, never raw yaml/serde.
- **Integrations:** the **two separated registers** — **Shared** (S12, read-only,
  entitled, no sign-in) and **Personal** (device-flow sign-in, `AuthIssue`
  expired/revoked rows offer re-sign-in). The visual/label separation is
  mandatory (D7.2).
- **Personal Key Sync (S13, new):** enable/disable syncing the user's own
  personal keys across his own machines; shows which of his machines are enrolled;
  honest about what is and isn't synced. Never touches shared-store material or
  git (mechanism open, §6).
- **Advanced:** poll cadence, diagnostics; no security-sensitive re-pointing.
- **Administration** (conditional): present only when `admin_capable`.

### 3.H Admin mode (S4) — Onboarding + Governance, no MDM, no fleet-as-center

Center of gravity (D3/D4): stand up the four-tier **component** repos, grant team
access (**entitlement**), configure the **central shared secret store**, and
author the **ecosystem seed** — all via GitHub. Maps to three-role-journeys §2b
(A0–A9).

**Onboarding** (do-once):
- **Handoff header** — renders `{publisher, admin, artifact_ref, next_owner}`.
- **Prerequisites & contacts** — names the GitHub org-owner sponsor + `AdminContact`
  (A0; closes G9).
- **GitHub topology** — teach + verify the `copilot-org` + `copilot-dept-<unit>`
  repos and org base-read (A1; closes G8).
- **Authors & SSH keys** — who authors each dept; on-device SSH keygen; team
  write grant = entitlement (A2/A3).
- **Central shared secret store setup** *(replaces the deleted MDM managed-key
  collector)* — connect Infisical/OpenBao, scope access by GitHub team, endpoint
  delivered via inherited org config (A4; D6).
- **Seed generator** (`admin/seed.rs`) — author `ecosystem.yml`
  (components/depts/pins/auth/policy_signers/telemetry) in-app and open the PR
  (A5; highest-value build; closes G6).
- **Access policy signers** — sign the capability policy; set CODEOWNERS/rulesets
  (A6).
- **Preflight verify** (`admin/preflight.rs`) — red/green over repos, teams,
  secret store, seed; `unknown` is never green; **no aggregate score, ever**
  (`PreflightReport`; A8; closes G7).

**Governance** (occasional):
- **Deprovision render (S8)** — a render of GitHub-access revocation +
  secret-store token rotation (D4 — no MDM wipe, no forced-key deprovision).
  `DeprovisionView`: `retained_dirty` prominent, `secrets_touched` must be 0,
  `secrets_alarm` honest (A9).
- **Analytics opt-in** — off by default; only when the org signs telemetry config.
- **Secret-store config** — read-only render of the inherited org config endpoint.

**Deleted from the prior Admin surface (D4):** the MDM profile generator, the
"19 `MANAGED_KEYS`" managed-key collector, the MDM upload walkthrough, and
**Fleet as the daily-ops center**. The `FleetView`/`FleetHostView`/
`FleetActionItem` DTOs in `types.ts` remain owner-gated and **deferred** — if any
per-host observability returns, it is a later, non-central read (still count, never
score), not the Admin home. `[UNBUILT]` today: handoff object, contacts, topology,
authors, secret-store setup, seed UI, policy signers, preflight UI, and the S11
department-join, S12 shared-integration, and S13 personal-key surfaces. The Rust
for `seed.rs`/`preflight.rs` exists; the native UI does not.

### 3.I Publisher (reference only)

Publisher Setup.app is the native quality precedent (`publisher-setup-visual-spec.md`).
Its one seam into this app: the structured Publisher→Admin handoff block
(artifact_ref + Team ID + version + update-signing status), rendered as the Admin
onboarding header. Unchanged by the domain correction.

## 4. The three journeys as native flows

Per the conformed `three-role-journeys.md`:

- **Publisher (§1):** Publisher Setup.app, P0–P11. Moments of truth: P3–P4 (the
  G2-cert trust trap) and P10 (one button, not terminal). Reused as-is.
- **Admin (§2):** Admin-mode Onboarding walks A0–A9 — repos → teams (entitlement)
  → authors/keys → central shared secret store → seed → policy signers →
  preflight verify; Governance holds deprovision-by-revocation + analytics.
  Moments of truth: A0 (every prerequisite is another person) and A5 (the seed
  generator ends hand-authored YAML). **No MDM half.**
- **User/Bob (§3):** U0 self-install (one path) → U1 wizard (Bob-answerable only)
  → **U2 department discovery + join (S11)** → **U3 personal sign-in (S5)** →
  **U4 entitled shared integrations, just-there (S12)** → U5 steady state (silent
  when fine) → U6 downward-only cadence sync → **U7 personal-key multi-machine
  sync (S13)** → U8 a change needs him (only his sign-in / his dirty WIP / a new
  department) → U9 conflict (author only) → U10 safety event (auto-acted,
  past-tense) → U11 update/rollback → U12 departure (server-side revocation, no
  device wipe). The sanctioned peaks are U3 ("I click sign-in and it works") and
  U11 ("it kept my work"); every negative emotion is an anti-pattern to design out.

## 5. Native quality principles + anti-patterns

**"Quiet Instrument" principles (reused verbatim from the prior pass — good craft):**

1. Menu-bar-first, silent-when-fine; success is the *absence* of signal (no
   celebratory green, no "All good").
2. Honest status over fake-healthy; holding states are first-class, not error
   screens; never fabricate Healthy — and never render **entitled-not-synced** as
   healthy.
3. Shape-first badges (map the 12 `BadgeState` tokens to SF Symbols), color as a
   second channel only; legible in grayscale / color-blind; `NSVisualEffectView`
   materials; system controls; SF Pro; Dynamic Type + Reduce Motion respected.
4. Restraint / as-little-app; a tiny popover action set (Sync now, What changed,
   **Join available**, Sign in, Preferences, Set up); no chat, no override, no
   re-pointing managed keys/endpoints.
5. Plain-language, never raw strings.
6. Structural role separation; Admin does not exist in the user's UI tree.

**Added by the corrected domain:**

7. **Components, never products.** The synced units are the CSE components across
   entitled layers; outputs (Insights/Pipeline/Method) never appear.
8. **Entitlement honesty.** Show the layers a user is entitled to (including
   entitled-not-synced as an honest, joinable slot); never invent access, never
   hide a genuine "you could join this."
9. **Shared vs personal integrations are two visibly distinct registers** — one
   inherited/read-only, one device-flow sign-in — never merged.

**Anti-patterns (owner-sourced + domain-corrected):**

- **A product/output catalog** — never list or sync Insights/Pipeline/Method or
  any built output.
- **MDM / fleet framing** — no `.mobileconfig`, no managed-key collector, no
  forced-domain screen, no fleet-dashboard-as-center, no two-lane install.
- The web-app look; a **purple filled header bar** (`#2D294E` survives only as the
  monochrome template-glyph tint, never a filled banner).
- Mismatched / emoji / decorative icons; raw error strings or `<<<<<<< HEAD`.
- **Em-dashes in any copy.**
- Time estimates / countdowns / progress-as-ETA.
- Any **computed number implying the app judged health** (no fleet score, no
  health rings, no sparklines, no preflight readiness score).
- A blended "Needs attention" that fails to name the failing component/layer/host.
- **Fake-healthy** of any kind — including rendering entitled-not-synced, or a
  shared integration whose secret failed to resolve, as green.

## 6. Open decisions & contract items for the checkpoint / TA

1. **`admin_capable` = first-run opt-in** (unmanaged only; no MDM grant path).
   TA to carry it as one explicit fact in the CLI `--json` contract.
2. **The `{publisher, admin, artifact_ref, next_owner}` handoff object** belongs
   in the CLI contract (parse-never-compute); TA to place it.
3. **`copilot layers` / `layers join` (D7.1)** are specified in
   `cli-contract.md` but marked "proposed, not yet in upstream WS-A scope" — must
   be folded into WS-A at freeze. The S11 surface depends on it.
4. **Entitled shared-integrations render (S12/D7.2) needs a DTO.** Today
   `types.ts` has `AuthIssue`/`SigninState` for the *personal* register only.
   The shared register needs its own read (e.g. `copilot integrations --json`
   distinguishing shared-entitled-no-signin from personal-device-flow), CLI-computed.
   Flagged to TA — the app must render it, not derive it.
5. **Personal-key multi-machine sync (S13/D7.3)** — carrier/mechanism is an open
   design item in `credentials-and-boundary.md` §7 (reconcile with per-device
   keypair locality). The surface is designed; the transport is not chosen. TA/CLI.
6. **`ProductView.product -> component` field rename (D2)** is code work the TA
   owns; the experience already treats it as the component view. Copy uses
   component/copilot names now.
7. **`WizardMode.managed` is vestigial (D4).** The shipped experience is the one
   guided window; TA to decide whether to retire the `managed` arm or leave it as
   a dead branch that renders nothing.
8. **`FleetView`/`FleetHostView`/`PreflightReport` fleet types are deferred**
   (owner-gated). Preflight (red/green, no score) stays as an Onboarding verify
   step; the collected-fleet dashboard is not an Admin center of gravity.
