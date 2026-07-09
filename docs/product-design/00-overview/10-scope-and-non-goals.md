> **Superseded framing.** This document predates the Copilot Solutioning Ecosystem (CSE) realignment. Its MDM/fleet framing and its use of "product" to mean a CSE tool are superseded. The corrected model is in `docs/reference/copilot-solutioning-ecosystem.md`; the decisions are in `docs/reference/cse-alignment-decisions.md`.

# Scope & Non-Goals

> **Provenance.** Grounded synthesis from `01-architecture/architecture.md`, `02-prd/prd.md`,
> `00-overview/product-brief.md`, and `CLAUDE.md` (the 5 invariants), **re-grounded in the owner
> interview of 2026-07-06** (`01-research/10-interviews/01-interview-self.md`), which surfaced new
> in-scope requirements (writable collaborative tiers, cadence-based pull, personal-layer content)
> and two hard open design problems. Every non-goal carries a rationale; each new scope item carries
> an honest **Evidence** stamp. Inline `<!-- TODO -->` marks genuine unsettled scope calls.
> Prerequisite: `00-vision.md`.

## In Scope (Initial Release)

The v1 scope is **macOS-only**, and its definition of done is a single, testable path
(`prd.md` §1): *an IT admin uses Admin mode to generate the seed + MDM profile, pushes the signed
app + profile via Jamf/Intune, and a non-technical employee's Mac silently self-provisions, stays
healed, and reports fleet health — with all 25 Critical/High red-team findings closed and the CLI
`--json` contract test green.*

Concretely, in scope:

- **The CLI `--json` / `flock` / `COPILOT_MANAGED_BY` contract** (WS-A, in the `copilot` repo) —
  the prerequisite that freezes the schema. The app cannot supervise a CLI it can't read
  machine-readably; nothing else starts until this is frozen.
- **Operator mode** — single-process Tauri shell; per-host status state machine + menu; host
  detection (Claude / Codex / both / neither); GUI first-run wizard with the **silent managed path**
  and fail-closed validation; SMAppService login item + crash-only watchdog; timer loops
  (sync / doctor / freshness) with battery/metered backoff.
- **Distribution & self-update** — Developer ID signing, notarize + staple, the cross-repo signed-CLI
  binary contract, watchdog-owned rollback, signed uninstaller.
- **MDM & security** — forced-domain security keys, managed login-item + notifications payloads,
  MDM-native deprovision (soft-then-hard), per-user everything.
- **The actor-competence × reversibility escalation model** with safety-channel-on-by-default.
- **Admin mode** — seed generator, repo/access scaffolding, capability-policy signing, **MDM profile
  generator**, preflight validation, fleet dashboard, deployment runbooks.
- **First-class IT documentation** — quickstart, per-MDM deploy guides, config reference,
  security-&-trust doc, ops/offboarding runbook (a first-class deliverable, versioned in the repo).

**Newly in scope (owner interview, 2026-07-06):**

- **Cadence-based propagation across the inheritance model (foundation → org → department →
  personal).** When an authorized person changes upstream content, Control Tower carries it onto
  every machine **quietly, on a cadence, without clobbering personal work.** A manual "sync now" is an
  escape hatch. `> **Evidence: OBSERVED**` — Pablo lives the hand-sync pain daily.
- **Writable collaborative tiers — org and department authoring.** A *trained* group writes
  org/department content (skills, agents, Knowledge Copilot content, CLI Copilot integrations) via a
  **markdown editor (Obsidian)** → save → push → sync across the department. Write access is **gated
  and earned**, starting with a few early-adopters and growing as demand rises.
  `> **Evidence: MODEL-IN-HEAD**` — never run with more than one writer; this introduces writable
  tiers that strain the "never-destroy / read-only mirrors" assumption (see open problems below).
- **Personal-layer content.** Individual, machine-local Knowledge Copilot content — e.g. **writing
  styles, which are plural and context-dependent** (email voice ≠ documentation voice ≠
  thought-leadership voice). This tier must be *readable/usable* by the ecosystem but **never leak
  upward** into a shared/public place.
  <!-- TODO (open, route to Knowledge Copilot design): what ELSE belongs in the personal layer for
       Knowledge Copilot + the CLI Copilot integration layer, beyond writing styles? -->
- **Non-technical merge-conflict resolution (in-scope requirement, mechanism TBD).** Two
  non-technical colleagues edit the same department file; sync produces a merge conflict; **neither
  knows Git.** The system must resolve it **elegantly, invisibly, non-technically** — ideally behind
  the scenes. This is a *requirement*, but the mechanism is an unsolved design problem (see below).
- **Personal↔shared leakage prevention (in-scope requirement).** A hard wall so private personal
  information can never be accidentally pushed into a public/shared tier. This is Anxiety #2 from the
  interview and a first-class safety requirement, not a nice-to-have.

**If we could only ship three things:** (1) the frozen CLI `--json`/`flock` contract, (2) the
single-process shell + silent-managed wizard that gets Bob provisioned and self-healing, and (3) the
Admin-mode MDM-profile generator that makes the silent path possible at fleet scale. Everything else
parallelizes off these (`prd.md` §2, critical path).

## Non-Goals

- **A second brain / any resolution logic in the app.** *Rationale:* it would duplicate a hardened
  pipeline and create two sources of truth; if a decision requires computing ecosystem state, it
  belongs in the CLI (`product-brief.md`; invariant #1). No health scoring, resolution, signature
  verification, prune, or wipe logic lives here.
- **Independent decision-making about systems of record.** *Rationale:* reads happen unprompted,
  writes confirm; it supervises and surfaces state that already lives in GitHub / MDM / Teams — it
  does not own it (`product-brief.md` non-goals).
- **An AI chat / conversational surface.** *Rationale:* it's a tower, not the pilot; adding a
  model-driven surface contradicts the AI philosophy and the never-compute invariant (`soul.md`).
- **A separate headless daemon or in-app fallback loop.** *Rationale:* the two-scheduler design was
  a concrete `copilot.lock`/prune race that could tear the `.claude/` tree; one signed binary +
  CLI-side `flock` is the resolution (invariant #2; fixes B-C1).
- **Windows (v1).** *Rationale:* macOS-first; Windows is a later six-shim re-skin over the shared
  Tauri core, deferred but not designed against (`architecture.md` §12, WS-I).
- **Multi-org-per-machine.** *Rationale:* ecosystem-level concern, deferred (`prd.md` §1).
- **Real-time / per-minute content refresh.** *Rationale:* propagation is deliberately
  **cadence-based, not real-time** (owner interview, 2026-07-06): "I can rarely imagine a moment where
  someone updates something that someone needs *right now*." A manual "sync now" escape hatch covers
  the rare urgent case; a constant live-refresh loop is explicitly the wrong model and adds churn,
  battery cost, and clobber risk for no real benefit. `> **Evidence: GROUNDED** (owner's framing).`
- **Monetization — any paid tier, enterprise SKU, or hosted service.** *Rationale:* Control Tower is
  **pure OSS, free forever** (DECIDED, Pablo 2026-07-06). Open source is not a pricing choice, it is
  the *trust guarantee* — an always-on agent that holds a live token and materializes
  executable-adjacent content is only auditable if it is fully open, so a paywalled or closed
  component would directly undermine the security posture that is the product's reason to exist. The
  purpose is to drive trust and adoption of the broader `copilot`/`cc` ecosystem; success is adoption
  + trust + reliability, never revenue. No paid tier, no enterprise SKU, no hosted service.
- **Designing for the reliable-power-user as the primary Operator-mode persona.** *Rationale:* Bob
  is not a reliable actor; the developer (Rosa/Dwayne) keeps using the CLI directly — Control Tower must
  not break that, but the end-user experience is designed for Bob, not for them
  (`redteam-use-cases.md`, Bob-agency recommendation).

### The line: "helping do X" vs. "doing X for them"

The escalation model *is* this line, made concrete (`architecture.md` §9): the app **does X for**
Bob when X is reversible and he can't judge it (re-materialize, auto-suspend a security-shadowing
override); it **helps** IT do X when X needs authority (held-major approval, policy signing); it only
**asks** Bob when he is the sole competent actor about his own data (commit dirty WIP; the one
sign-in). It never asks Bob to make a decision he has no basis to make.

## Open Design Problems (in-scope requirements, unsolved mechanisms)

These are **first-class requirements** the interview surfaced whose *mechanism* is genuinely
unsolved. They are flagged here so the architecture / security / threat-model work owns them; Pablo
is explicitly unsure what is technically possible.

| Open problem | Requirement | Why unsolved | Route to |
|--------------|-------------|--------------|----------|
| **Non-technical merge conflict** | Two non-technical colleagues edit the same department file → conflict → resolve *elegantly, invisibly, non-technically*; neither knows Git | Writable collaborative tiers strain the "never-destroy / read-only mirrors" assumption; trained-few-writers-first shrinks blast radius but does not remove it. `> **Evidence: MODEL-IN-HEAD**` | architecture / security work |
| **Personal↔shared leakage** | A hard wall so private personal content can never be pushed into a public/shared tier (Anxiety #2) | Boundary-crossing is the nightmare scenario; needs an enforced, not merely conventional, wall | architecture / security work |
| **Credentials through a pull-based model** | What carries secrets through cadence-based inheritance when a company has **no cloud secret store**? GitHub — and if so, how, *safely*? | Unsolved; a pull-based model with no secret store has no obvious safe carrier | security / threat-model work |
<!-- TODO (Pablo): the credentials carrier is genuinely undecided. Do not assume GitHub is safe until
     the threat model says so. -->

## Anti-Features

Things that would actively make the product worse — say no even if requested:

- **Any bypass flag** (`--skip-verify`, `--force`) or a "lower-bar" mode to unstick a machine — the
  always-on agent's entire safety claim is that it runs the *same* pipeline with *zero* bypass flags
  (`architecture.md` §8.3; invariant #4).
- **`KeepAlive=true`** — resurrects the app after a clean Quit and crash-loops a bad build (B-C2).
- **Reading security-sensitive keys from the user preference domain** — a supply-chain preference-write
  attack repoints the update feed/mirror to achieve RCE (B-C5).
- **Screen-scraping human CLI output** — a misread `fail`→`pass` shows green over a red pipeline; the
  single highest integration risk (`architecture.md` §6).
- **Handing Bob approval decisions to clear a badge** — trains blind-approve or indefinite drift
  (A-H11); and notifying Bob on things he can't action, which burns the credibility of the security
  alert that matters (A-M15, C3).
- **A "make it Healthy anyway" override** — false-Healthy over a foundation-only or mis-provisioned
  machine is the exact failure class the fail-closed states exist to prevent (A-C1, H7, H12).

## Constraints

**Technical.**
- Tauri v2, Rust core + minimal web UI, **single process**, macOS-first (`CLAUDE.md`).
- **Developer ID, not Mac App Store** — the sandbox forbids spawning `copilot` (`architecture.md` §7).
- Userland-only entitlements: **no admin, no privileged helper**. Per-user everything ($UID
  tree/keychain/login/watchdog); no writable `/Users/Shared` state.
- Invoke the CLI by **absolute, translocation-safe path**, never bare `copilot` (avoids the
  `gh copilot` collision; `CLAUDE.md`).
- The CLI `--json` contract is the whole safety boundary — schema drift = silent security bypass;
  bidirectional schema gate, missing security fields fail closed (`prd.md` §13, risk).

**Business / trust.**
- **Open source is a requirement AND the go-to-market, not goodwill** — an always-on agent holding a
  live token and auto-materializing executable-adjacent content must be auditable for an enterprise to
  trust it (`architecture.md` §1). Open source + reproducible builds + two-of-N signing are the trust
  basis. Control Tower is **pure OSS, free forever** (DECIDED, Pablo 2026-07-06): the same openness
  that satisfies the security review is the adoption strategy for the wider ecosystem — success is
  adoption + trust + reliability, not revenue.
- **Never-destroy is a hard line** — may freely re-materialize `.claude/` and re-clone read-only
  mirrors; **never** touches a dirty personal working tree (invariant #3).

**Compliance / privacy.**
- Telemetry is **opt-in, org-scoped (never ENAC), PII-minimizing** — a personal item name must be
  *un-emittable by construction* (`architecture.md` §9). Safety escalation is split from analytics
  and is on by default for managed machines (content-free signals only).
- Deprovision guarantees "no secret ever materialized," **not** "exfiltration undone" — an
  offline/powered-off machine cannot be wiped remotely; document this honestly (`architecture.md` §8.3).

## Design Philosophy

### Principle 1: Parse, never compute
Control Tower calls CLI verbs and renders the result. It contains no resolution, sync, signature, or
wipe logic of its own. **The test for any feature:** *does it require computing ecosystem state?* If
yes, it belongs in the CLI, not here. If Control Tower vanished, the CLI would still be correct.

### Principle 2: Route by actor-competence × reversibility, not event-class
Auto-act on reversible things the user can't judge; escalate to IT what they can't action; ask the
user only for non-deferrable decisions about their own data. **The test:** *for this event, who is
the sole competent actor, and is the action reversible?* — the answer picks the lane. A notification
Bob can't act on is a regression.

### Principle 3: As little app as possible (Rams)
One signed binary, no daemon, no fallback loop, a tiny web UI, no heavy framework. Trust comes from
*less* surface, not more. **The test:** *does this add surface area an enterprise security review has
to audit?* Every added capability is weighed against the auditability that is the product's moat. If
you find yourself re-implementing resolution/sync in Rust, stop.

## Integration Boundaries

| Will NOT Integrate With | Reason |
|-------------------------|--------|
| GitHub as a system of record (repos, teams, CODEOWNERS) beyond what the CLI/`gh` already does | It supervises and surfaces; it does not replace the source of truth (`product-brief.md`) |
| MDM as anything but a *consumer* of generated profiles + the deprovision channel | Deprovision must be MDM-native, not app-contingent; the app is the face, MDM is the enforcement channel (A-C4) |
| Teams/HR directories beyond reading the department pick-list at wizard time | Not a directory product; it reads, it doesn't own org structure |
| Arbitrary third-party update feeds / mirrors via user config | Trust roots are compiled-in code, not config; security keys honored only from the forced/managed domain (B-C5) |
| Any cloud/remote session or "start a session for me" backend | It bridges the local machine's CLI; it is not a remote-execution service |
| Mac App Store distribution | Sandbox forbids spawning the CLI (`architecture.md` §7) |

## Future Considerations

| Feature | Why Out of Scope Now | Conditions for Future Inclusion |
|---------|----------------------|--------------------------------|
| **Windows re-skin** | macOS-first; six OS-boundary shims (tray, Task Scheduler, EV/SmartScreen, MSI/winget, Credential Manager, Intune/GPO) | Shared Tauri core stable on macOS; the six boundary shims designed as re-skins from day one (WS-I, P4) |
| **First-class kiosk / lab (shared-machine) support** | Machine-credential path (`AuthMode=gh-app`) is specified but its depth is undecided | <!-- TODO: architecture §11.3 open decision — first-class machine-credential path now, or defer? Needs Pablo's call on how many lab/kiosk fleets are real targets. --> |
| **Publish-webhook fast revocation** | Urgent org changes propagate only as fast as the freshness poll; the webhook is opt-in/org-hosted | <!-- TODO: architecture §11.2 / A-M16 — accept the freshness-poll floor, or require the webhook for orgs needing fast kill of a compromised skill? --> |
| **Codex host at full parity** | Control Tower is host-agnostic by design, but Codex Copilot's own installer maturity gates the Codex column | <!-- TODO: architecture §11.4 — confirm Codex installer parity timing before the Codex column ships at parity. --> |
| **Opt-in analytics / adoption telemetry** (beyond content-free safety signals) | Analytics stays genuinely opt-in per org; only the safety channel is on-by-default | Org explicitly opts in via `ecosystem.yml`; PII-minimizing schema proven (G1–G2) |
| **Multi-org-per-machine** | Ecosystem-level concern; v1 is one org per machine | Ecosystem resolver supports it upstream; a real multi-org customer exists |
