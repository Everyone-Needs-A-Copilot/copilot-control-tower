# RESUME-HERE — Copilot Control Tower (post-build pickup)

**Read this first when you come back.** The app is *built*. This document is the
bridge from "9 milestones of code that renders mocks" to "a signed, live product."
It supersedes [`HANDOFF.md`](HANDOFF.md) (which was the *build* brief — now done).

> **Kickoff (paste into a fresh Claude Code session in this repo):**
> *"Read `docs/RESUME-HERE.md` end-to-end. Apple account is approved now — let's continue."*

Paused **2026-07-08** because Apple Developer Program enrollment is **awaiting
approval**. Nothing is blocked structurally; we're waiting on that one gate, and
banking the rest of the owner-only items so the restart is a checklist, not an
archaeology dig.

---

## TL;DR — the state in five lines

- **All 9 milestones are built, sec+qa gated, and pushed.** ~860 tests green on macOS.
- The app **renders mocks** for everything that needs live infra/credentials. That's by design — the seams exist; only the far ends are stubbed.
- **The only external blocker is Apple approval** (for signing/notarization). Everything else is a decision or an endpoint *you* own.
- **I (Claude) can make real progress with zero input from you** on exactly one big front: de-mocking the CLI contract (WS-A) in the `claude-copilot` repo.
- When you return: do the **Signing** section, then tell me to start **WS-A de-mock**. Those two turn "built" into "real."

---

## Where the code lives (exact state at pause)

| Repo | Path | Branch | Pushed? | Merged to `main`? |
|---|---|---|---|---|
| **Control Tower (the app)** | `/Volumes/Dev/Sites/COPILOT/copilot-control-tower` | `app-build` (→ `8dd4f71`) | ✅ origin/app-build | ❌ **not yet** |
| **CLI engine (`cc`)** | `/Volumes/Dev/Sites/COPILOT/claude-copilot` | `ws-a-doctor-slice` (→ `2a02a45`) | ✅ in sync | ❌ (own PR track) |

**Open decision at restart:** merge `app-build` → `main` (open a PR for review), or
keep iterating on the branch. Recommendation: open the PR now so the build is
reviewable, keep landing follow-ups on the branch until signing is wired.

**Build gotcha (don't lose this):** cargo in the control-tower repo needs
`PATH="/usr/bin:$PATH" CC=/usr/bin/cc` because the `copilot` CLI is installed as
`cc` and shadows the C compiler for the `aws-lc-sys` build script. `npm run build`
for the web UI is unaffected.

---

## ▶ WHAT YOU DO WHEN APPLE APPROVES (owner-only — I can't do these)

Ordered by leverage. #1 is the whole reason we paused.

### 1. Signing & notarization (unblocks the macOS release path — M4)
This is what the Apple approval gates. Once your membership is active:
- **Developer ID Application certificate** — Developer portal → Certificates → create
  a *Developer ID Application* cert (this signs a Mac app distributed **outside** the
  App Store, which is us). Export it as a `.p12` + password.
- **Notarization credential** — App Store Connect → Users and Access → Integrations →
  **App Store Connect API key** (preferred), *or* an app-specific password on your
  Apple ID. `notarytool` uses this to notarize + staple.
- **Hand me the identity name** (e.g. `Developer ID Application: Your Name (TEAMID)`)
  and I wire the real `codesign` → `notarytool submit` → `stapler` path. The release
  scripts already read the identity from an env var, so this is a config drop, not a
  rewrite.
- Note: an **Individual** membership is fine for this — certs will carry *your name*,
  not a company's. If you want the org name on the signature instead, that's the
  Terry-Hughes-org path (see [`06-deployment/requirements.html`](06-deployment/requirements.html)).

### 2. Update-signing keys (minisign 2-of-N — M4/M7)
- **Decide the second key-holder** (who besides you holds a self-update signing key).
  `k ≥ 2` signatures required; roots are compiled-in code, not config.
- Then I generate the keypair(s); you custody the private keys offline; the public
  roots get compiled in. Until this exists, self-update verifies a placeholder root.

### 3. Infra endpoints (the four URLs — M6/M7)
All *your* infrastructure. The app has content-free seams pointed at mocks for each.
Give me a real URL (or say "later, keep it mocked") per line:
- **Telemetry ingest** endpoint (opt-in, content-free, default OFF).
- **Fleet collector** query API (feeds the Admin/fleet dashboard).
- **IT / AdminContact** delivery channel (where EscalateIt signals go).
- **Update feed** URL (where the signed self-update manifest is served).

### 4. A test-enrolled Mac (MDM — M5)
To verify the forced-domain gate end-to-end with a real `.mobileconfig`. The
generator is built and unit-tested; only a live MDM-enrolled machine proves the
boundary. Owner-gated: needs your MDM (or a test profile installed).

### 5. A real IT person on Admin/fleet (validation — M7)
Those surfaces are stamped **UNVALIDATED HYPOTHESIS** (SOUL Founding Decision #9).
No real operator has touched them. This is a validation gap, not a code gap —
find one IT admin to walk through it before treating Admin mode as proven.

### 6. Windows (M9)
Needs a **Windows box + Authenticode cert** to build/sign/test the re-skin. It's
all `#[cfg(windows)]`-gated and cannot be verified on this Mac. Lowest priority
until macOS ships.

---

## ▶ WHAT I START ON RESUME (no input from you needed)

### WS-A CLI de-mock — the single highest-value autonomous track
The app parses a **frozen `--json` contract**; several verbs it renders don't exist
in the `cc` CLI yet, so the app is built against mocks/fixtures. Implementing the
real verbs in `claude-copilot` is on-machine work needing nothing from you, and it's
the thing that most moves this from "renders a mock" to "renders the real CLI":

- **`cc auth` device-flow** (RFC 8628) — the wizard sign-in seam (M3 gap D-3-M3).
- **`cc layers add`** — the Settings layer-manifest authoring verb (M2 fallback D-1).
- **Per-layer status field** in `doctor.schema.json` — so the app renders richer
  per-product/per-layer copy without computing (M1 decision D-1, in memory as a
  follow-up).
- **`telemetry.enabled` / `telemetry.endpoint`** field on the `cc --json` contract —
  resolves the M7 carrier-divergence gap (G-M7-1) so opt-in is read from a trusted
  carrier, never an unsigned/user domain.

Each lands the same way the existing WS-A slices did: schema first (freeze the
shape), fail-closed parser, then the verb. When these exist, I swap the app's mocks
for real calls verb-by-verb.

**When you're back, just say:** *"Start the WS-A de-mock, beginning with `cc auth`."*

---

## Open decisions still needing your judgment (batch these on return)

These were deferred as owner-unratified during the build; none block the restart,
but they're the questions I'll ask when the relevant work comes up:

- **Second signing-key holder** (item 2 above).
- **Real values or "keep mocked"** for the four infra endpoints (item 3).
- **Stalled-onboarding threshold** and **update retry/backoff** params (M7 defaults).
- **Merge `app-build` → `main`** now, or keep iterating on the branch.
- **Individual vs org signing identity** — which name goes on the signature
  (decided partly by whether Terry's org account frees up).

---

## The map — where everything is documented

- **The invariants (govern everything):** [`CLAUDE.md`](../CLAUDE.md) — the 6 rules, verbatim.
- **The soul + feature filter:** [`SOUL.md`](../SOUL.md).
- **The contract the app parses:** [`01-architecture/schemas/`](01-architecture/schemas/) + [`cli-contract.md`](01-architecture/cli-contract.md) + [`error-taxonomy.md`](01-architecture/error-taxonomy.md).
- **Signing + infra explainer (role/tier-tiered, HTML):** [`06-deployment/requirements.html`](06-deployment/requirements.html).
- **Per-milestone decisions & gaps:** the session memory files in
  `~/.claude/projects/-Volumes-Dev-Sites-COPILOT-copilot-control-tower/memory/`
  (`m1`…`m9` decision notes, `ws-a-per-layer-status-followup`, `neutral-role-language`).
  These carry the owner-gated lists per milestone and the "why" behind each gap.

---

## What "done" looked like at pause (so you can trust the restart)

Every milestone was sec+qa gated with **mutation-tested** invariant fitness tests.
Verified structurally, not by inspection:
- **False-Healthy is impossible** — the app can't compute a green state; it only renders CLI verdicts.
- **Secrets never leak** — inheritance content carries only `requires_secret: <NAME>` references; fail-closed leak-scan on every writable push.
- **Crash-only never resurrect-always** — launchd `KeepAlive={SuccessfulExit:false}`; Windows Task Scheduler failure-restart-with-cap, never periodic-repeat.
- **No computed fleet score** — the dashboard renders CLI-computed per-host worst-wins, no "94/100."
- **Telemetry is opt-in, default OFF**, content-free.
- **Windows code is `#[cfg(windows)]`-gated out** — macOS unregressed; Windows build owner-gated.

Personas were neutralized before pause (Earl / Rosa / Dwayne / Bob / Ada / Mira /
Pablo) for the OSS launch — no stereotyped placeholder names remain in docs or code.
