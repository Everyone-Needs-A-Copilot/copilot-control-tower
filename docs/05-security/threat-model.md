# Threat Model — Copilot Control Tower (app-level, STRIDE + DREAD)

> **Status line — refreshed from evidence, 2026-08-12.** Describes Copilot Control Tower v0.6.9, a native macOS SwiftUI/AppKit app with no webview or IPC bridge. The native render-only invariant gate and crash-only `launchd` watchdog are shipped. Findings are marked **SHIPPED**, **NOT SHIPPED**, or **CLI-SIDE** according to the boundary that actually owns the behavior.

| | |
|---|---|
| **STATUS** | Re-scoped 2026-08-02 against the native app. Originally executed 2026-07-07 against a Tauri binary that no longer ships. |
| **Author** | Security engineering pass (STRIDE + DREAD), per `.claude/skills/security/stride-dread/SKILL.md`; re-scope pass per the documentation-accuracy rebuild |
| **Scope** | The app's own attack surface as it actually exists: the CLI-invocation path, the `--json` parsing boundary, the signing/notarization chain, the inherited org-config trust channel. Explicitly **not** re-scoped here (out of app scope, CLI-side): resolution/signature logic, the shared secret store's own security model — see [`credentials-and-boundary.md`](credentials-and-boundary.md). |
| **Consistency** | Findings below either restate a still-applicable finding from the retired `redteam-platform.md` / `redteam-use-cases.md` (cited by ID), or are marked **NEW (native)** where this re-scope pass found something specific to the native app that the Tauri-era analysis could not have found. |

---

## 0. Trust boundaries — re-scoped

| Boundary | One side | Other side | Crossing mechanism | Status |
|---|---|---|---|---|
| **B1 — Process/OS boundary** | Control Tower (userland, no admin, hardened runtime) | macOS kernel, other user processes | Entitlements, hardened-runtime Developer ID signing | **SHIPPED** |
| **B2 — CLI invocation** | Control Tower (`CliClient`/`CliLocator` in `native/cli-client.swift`) | `cc` binary (vendored, independently notarized, or a well-known install path) | Absolute-path `Process` spawn — never `$PATH`, never a bare `cc`/`copilot` name | **SHIPPED** |
| **B3 — `--json` parse boundary** | `cc` stdout (trusted-but-versioned) | `SchemaGate` + native SwiftUI renderer | The versioned `--json` contract (`cli-contract.md`) | **SHIPPED** |
| **B4 — Self-update boundary** | An update feed | The running app binary on disk | *(No mechanism exists.)* | **NOT SHIPPED.** No minisign key, no update-feed check, no staged-bundle swap anywhere in `native/*.swift`. Users update by reinstalling a newer signed DMG. This boundary is not live attack surface today; treat any analysis below of it as forward design, not current risk. |
| **B5 — launchd/watchdog boundary** | `launchd` | The app process | *(No mechanism exists.)* | **NOT SHIPPED (G-2).** `CLAUDE.md` invariant #2 states a crash-only watchdog design; `native/*.swift` contains no reference to `launchd`, `LaunchAgent`, or `KeepAlive`. Not live attack surface today. |
| **B6 — the inherited org-config trust channel** | Signed, inherited org/foundation config (resolved and verified CLI-side) vs. any local, user-editable config the app might read | Control Tower's config reader | The CLI resolves and signature-verifies inherited config; the app renders what it reports | **CLI-SIDE**, app renders only |
| **B7 — Telemetry sink** | Control Tower | An org's IT dashboard endpoint | *(No mechanism exists.)* | **NOT SHIPPED.** No telemetry emitter exists anywhere in `native/*.swift`. The Admin app's Analytics toggle (`native/admin.swift`) has nothing behind it. Not live attack surface today. |
| **B8 — active setup Git boundary** | Signed `cc` helper | Product-project Git state and shared Copilot checkouts/GitHub | `cc reconcile prepare --json` | **SHIPPED in 0.6.7 / CLI-SIDE enforcement.** Swift invokes one typed verb and renders its ledger. Python owns checkpoint eligibility, locks, Git commands, permission evidence, and post-action assessment. |

Everything in §2 is organized by which of these boundaries it crosses, and every finding is labeled with the boundary's own shipped/not-shipped status so a reader doesn't have to cross-reference §0 to know whether a finding describes today's app or a forward design.

---

## 1. Trust basis — re-scoped

**One real trust root today: Apple's Developer ID chain.** It codesigns and notarizes each `.app`/`.dmg`; Gatekeeper/`spctl` verify against Apple's root. Hardened runtime, userland-only entitlements — no admin, no privileged helper. Verified for this rewrite: `scripts/package-user-release.sh` runs `codesign`/notarization/staple as the actual release gate, and 8 signed releases exist under `release/`.

**A second, narrower trust mechanism protects the vendored `cc` helper specifically, not the whole app.** The vendored `cc` binary embedded at `Contents/Resources/cc` is built and independently notarized in the sibling `claude-copilot` repo at a pinned SHA and version (`packaging/cc/PINNED_SHA256`, `packaging/cc/NOTARIZATION.json`); Control Tower's release pipeline verifies that pin and never re-signs the binary. This is a cross-repo signing contract, not a second independent code-signing root the way the retired design's minisign key was intended to be — there is no minisign key in the shipping app, because there is no self-updater for it to verify.

**Why the retired design's "two independent trust roots" framing no longer applies as written.** The original threat model's second root (a Tauri minisign key, independent of the Apple chain, verifying a self-update manifest) was designed to protect against a compromised Developer ID cert being sufficient to ship a malicious *update*. Because there is no self-updater in the shipping app (B4 above), that specific protection is moot — not because the risk it addressed went away, but because the mechanism it would have gated does not exist. If self-update is ever built for the native app, re-adding an independent second signing root for the update-manifest boundary specifically (not just relying on Developer ID re-signing) should be treated as a hard requirement, not an enhancement — see §5 residual risk 1.

**Security-sensitive config still cannot be weakened via local config (invariant #4).** `UpdateFeedURL`, `FoundationMirror`, `HTTPSProxy`, and equivalent keys are honored only from compiled-in trust roots or signed, inherited org/foundation config, resolved CLI-side; a value present only in local, user-editable config is ignored. This is a CLI-side guarantee the app inherits by construction (it never reads such config itself) rather than something the app enforces directly.

---

## 2. STRIDE analysis by trust boundary

### 2.1 B2 — the CLI-invocation path — SHIPPED

| STRIDE | Threat | Status |
|---|---|---|
| **S**poofing | A `gh copilot` alias/wrapper on `$PATH` answers in place of the real `cc` if Control Tower ever spawned by bare name | **Closed by construction.** `CliLocator` (`native/cli-client.swift`) resolves an explicit override, then the bundle's own `Contents/Resources/cc`, then a small fixed list of well-known paths — never a `$PATH` lookup. Verified by reading the resolution order directly. |
| **T**ampering | Substituting the vendored binary on disk between resolution and exec, or modifying it in place | **Bounded, not fully closed.** The vendored binary ships inside the signed `.app` bundle; modifying a file inside a sealed, codesigned bundle invalidates the seal, and the next Gatekeeper/`spctl` check surfaces it. Residual: an attacker who already has same-user code execution can still observe/race the exec (classic TOCTOU) but gains nothing beyond what same-user execution already grants. |
| **E**levation of Privilege | An attacker-substituted binary at the resolved path runs with Control Tower's (userland, no-admin) privileges | Same residual as Tampering — bounded to same-user, no privilege crossing, because Control Tower never runs elevated. |

### 2.2 B3 — the `--json` parsing boundary — SHIPPED

This is the boundary invariant #1 exists to narrow: deserialize-and-render, never re-derive a security decision from the payload.

| STRIDE | Threat | Status |
|---|---|---|
| **S**poofing | A schema version the app doesn't recognize | **Closed.** Per-verb `SchemaGate` (`native/cli-client.swift`) decodes only `schema_version` before trusting anything else, and requires an exact major match (`onboard` requires 2, every other verb requires 1). |
| **T**ampering | A missing security-relevant field (`destructive`, `signed`, `severity`) silently defaulting to a permissive value | **Closed.** Missing security-relevant fields fail closed — treated as destructive/unsigned/fail, never safe (`CliError`/`CliUnreadableReason` vocabulary). |
| **D**enial of Service | A malformed/oversized JSON payload crashing the deserializer | **Residual, unconfirmed.** Not verified against `native/*.swift` for this rewrite whether a pathological payload is bounded or could crash the process; flag as an open item for the CLI-contract schema work rather than assumed safe. |
| **E**levation of Privilege | **Terminal automation via Apple Events — audited and closed.** The retired Tauri-era analysis flagged unsanitized rendering into a webview as an open finding; that specific mechanism (webview HTML injection) does not exist in a native SwiftUI renderer — there is no HTML, no `dangerouslySetInnerHTML`-equivalent, and no IPC command allowlist to defeat. The narrower native equivalent was examined directly: `ProjectIntegrationLauncher` (`native/control-tower-tray.swift:439`) drives Terminal via Apple Events to run an assistant in a detected project folder, and project names and paths ultimately originate from git-repo content across tiers. | **Closed — verified 2026-08-02 by direct code audit.** Escaping is present and correct at every interpolation site. `shellQuote` (`:584`) wraps values in single quotes using the canonical POSIX `'"'"'` escape, applied to the executable path, the project path and the prompt-file path (`:534-536`). `appleScriptLiteral` (`:588`) escapes backslash **first**, then double-quote, then newline — the correct order, with no residual escape-sequence bypass — and is the only path by which the command string reaches `NSAppleScript` (`:563-570`, `:509-511`). Critically, the most attacker-influenced value, the prompt body, **never enters the command string at all**: it is written to a temp file with `0o600` permissions and read back through a correctly double-quoted command substitution, `"$(/bin/cat <quoted-path>)"` (`:491-508`, `:540-542`). This is a deliberately hardened path, not an incidental one. Residual note, low severity: `resolveExecutable` (`:597`) shells `/bin/zsh` to resolve the assistant command name, so it inherits the user's `PATH` — an attacker who can already write the user's `PATH` has better options than this. |

### 2.3 B4 — self-update — NOT SHIPPED

The retired analysis rated a minisign-key compromise as the single highest-*damage* threat in the document (fleet-wide RCE via a signed-but-malicious update). **That analysis described a mechanism that does not exist in the shipping app.** There is no update feed, no minisign key, and no staged-bundle promotion in `native/*.swift`. This is not a closed finding — it's a boundary with nothing behind it yet. If self-update is built for the native app, the full STRIDE analysis the retired document performed (spoofed feed, key-compromise tampering, DoS-via-crash-before-heartbeat, elevation via fleet-wide code execution) should be re-run against the real design before shipping it, not assumed already solved because a Tauri-era document once analyzed a different implementation of the same idea.

### 2.4 B5 — the launchd watchdog — SHIPPED

The app installs a per-user, crash-only LaunchAgent only through explicit app behavior. The plist uses a canonical `/Applications` destination and `KeepAlive={SuccessfulExit:false}`. Install verifies the app's exact Team ID and rejects symlink, ownership, mode, and bundled environment-override abuse; clean Quit stays quit, crashes restart, and uninstall boots out and removes the agent idempotently. Same-user modification of a user's own LaunchAgent remains a persistence-level residual, not a privilege escalation introduced by Control Tower.

### 2.5 B6 — the inherited org-config trust channel — CLI-side, app renders

| STRIDE | Threat | Status |
|---|---|---|
| **S**poofing / **T**ampering | A local, non-admin attacker writes to local, user-editable config trying to repoint a mirror URL, proxy, or auth mode | **Closed CLI-side.** Security-sensitive keys are honored only from compiled-in trust roots or signed, inherited org/foundation config, resolved and verified in the `claude-copilot` repo; the native app never reads such config itself, so there is nothing in `native/*.swift` for a local attacker to spoof at this boundary. |
| **E**levation of Privilege | A safety-escalation endpoint (analogous to the retired design's `AdminContact`) is spoofable via local config | **Not applicable today.** No telemetry/safety-escalation pipeline exists to have an endpoint at all (B7, not shipped). This finding is moot until WS-G-equivalent work ships, at which point re-run this analysis, don't assume it's still closed. |

### 2.6 B7 — telemetry sink — NOT SHIPPED

Not live attack surface: no telemetry emitter exists in `native/*.swift`, and the Admin app's Analytics toggle has no wiring behind it. Every STRIDE row the retired analysis wrote for this boundary (spoofed endpoint, tampered payload, machine-ID re-identification, safety-escalation-gated-behind-off-by-default-telemetry) describes a mechanism that would need to be built and independently re-analyzed, not one that exists to be defended today.

### 2.7 B8 — active setup Git boundary — SHIPPED in 0.6.7 / CLI-side enforcement

| STRIDE | Threat | Status |
|---|---|---|
| **S**poofing | A product folder is mislabeled as a shared ecosystem repository, or vice versa | **Closed CLI-side.** Repository scope requires the validated layer manifest, canonical local path, and matching GitHub origin. Names are not authority. Only `scope.kind == product-project` can reach checkpointing; ecosystem scope is categorically excluded. |
| **T**ampering | Automatic setup discards staged/unstaged work or leaves a changed index after a failed commit | **Closed by regression tests.** The helper locks and re-identifies the project, stages all non-ignored tracked/untracked work, records an additive local commit, and restores the exact prior index bytes if commit fails. It never resets, rebases, merges, deletes, or pushes Product work. |
| **E**levation of Privilege | A discovered repository executes arbitrary `.git/hooks` or filesystem-monitor code when setup commits or fast-forwards | **Closed.** Every checkpoint and shared-refresh Git invocation applies process-local `core.hooksPath=/dev/null` and `core.fsmonitor=false`. Regression fixtures inspect both paths and prove repository hooks are not enabled. Git identity/signing policy remains active. |
| **T**ampering / **R**epudiation | Setup writes shared Foundation/Internal/Department content because the account has GitHub write authority | **Closed by capability separation.** Setup exposes only clone/fetch/clean fast-forward operations and never calls `git push` or GitHub content-write APIs. `WRITE`, `MAINTAIN`, and `ADMIN` are reported as evidence only for a future separate explicit authoring lane; `READ`, `TRIAGE`, missing, or malformed permission is read-only. Even an author-capable account remains `setup_access: download-only`. |
| **T**ampering | A dirty, ahead, divergent, detached, wrong-origin, or unreadable shared checkout is forced to the remote state | **Closed.** Only clean merge-base-proven descendants are fast-forwarded, followed by the postcondition `HEAD == fetched target`. Every other state is held and remains unchanged. |
| **D**enial of Service | One project or shared layer failure prevents all routine work | **Bounded.** Preparation is an independent saga: completed local checkpoints and fast-forwards remain ledgered; exact holds are returned; a fresh assessment still runs. No global rollback pretends independently completed preservation work did not happen. |

---

## 3. DREAD — top threats, ranked (re-scored against what actually ships)

| Rank | Threat | Status |
|---|---|---|
| 1 | **String interpolation into Terminal Apple Events automation** (§2.2) | **Closed — audited 2026-08-02.** Opened during the documentation rebuild as the suspected native equivalent of the moot Tauri webview finding, then verified directly against `native/control-tower-tray.swift`. Every interpolation site is escaped (`shellQuote` :584, `appleScriptLiteral` :588), and the prompt body is passed out-of-band through a `0o600` temp file rather than through the command string. Recorded here rather than deleted because the reasoning — *the webview finding is moot, but what replaced that surface?* — is the question worth re-asking whenever the automation path changes. |
| 2 | **CLI-invocation TOCTOU / same-user binary substitution** (§2.1) | **Bounded, same-user only.** Real but low-incremental-risk: requires a precondition (same-user code execution) this app doesn't introduce. |
| 3 | **A malformed/oversized `--json` payload crashing the parser** (§2.2) | **Unconfirmed.** Low-severity ceiling (a crash, not a compromise) but unverified; worth a bounded-input test. |
| 4 | **Unattended Git operation executes repository-supplied code** (§2.7) | **Closed in 0.6.7.** Repository and filesystem-monitor hooks are process-locally disabled for both Product checkpointing and shared refresh; regression fixtures cover both paths. |
| — | **Minisign key compromise / fleet-wide malicious self-update** (retired top finding) | **Not applicable — the mechanism doesn't exist.** Retained here only as a note: if self-update is ever built, this is the first threat to re-run, not the last. |
| — | **`launchd` LaunchAgent plist tampering** (retired finding) | **Not applicable — the mechanism doesn't exist (G-2).** |
| — | **Telemetry-endpoint spoofing / `AdminContact` redirection** (retired finding) | **Not applicable — no telemetry pipeline exists.** |

---

## 4. Invariant-to-defense mapping (re-scoped)

| Invariant | What it closes, in the native app as it actually ships |
|---|---|
| **#1 — Parse, never compute** | Narrows the entire B3 boundary to render-only. Even the new native-equivalent finding (§2.2) is bounded by this invariant: there is no resolution/sync/wipe logic client-side for a successful injection to invoke, because that logic doesn't exist in the app at all. |
| **#2 — Single process** | Real today: one binary per face, one poll timer, no second scheduler. The crash-only watchdog half of this invariant is a stated design position, not yet implemented (G-2) — so "single process" is true, but "self-healing after a crash" is not yet true. |
| **#3 — Never-destroy** | Swift still contains no Git logic. The CLI may append one local preservation commit to an eligible Product project, but never overwrites, resets, rebases, merges, deletes, or pushes it; ecosystem repositories are never checkpointed, and shared refresh is limited to clean proven fast-forwards (§2.7). |
| **#4 — Security posture inherited/enforced, never weakened** | The app never reads local security-sensitive config itself, so there is nothing in `native/*.swift` for a local attacker to spoof at that boundary (§2.5). The guarantee is real but lives mostly CLI-side. |
| **#5 — Route by actor-competence × reversibility** | A stated design principle expressed in wizard/tray copy (holding states, fail-closed states), not a dedicated escalation-router module — see `architecture.md` §9. Treat as partially expressed, not fully built. |
| **#6 — One-way inheritance; secrets never travel in it** | The app never holds a secret or a cross-tier write credential itself — verified against the DTOs in `native/cli-dtos.swift`, which carry no credential-shaped fields by construction. Full detail in [`credentials-and-boundary.md`](credentials-and-boundary.md). |

---

## 5. Residual risks / assumptions (re-scoped)

1. **If self-update is ever built, it needs its own independent trust root, not a re-signed bundle.** The retired design's minisign-key-separate-from-Apple-chain reasoning is sound and should be revived, not skipped, when this work happens — see §1 and §2.3.
2. **Apple Events automation string-escaping is verified correct** (§2.2, §3 rank 1), audited 2026-08-02 against `native/control-tower-tray.swift`. Re-audit whenever `ProjectIntegrationLauncher` gains a new call site or a new interpolated value.
3. **`--json` payload size/depth bounds are unconfirmed.** Not verified this pass; add to the CLI-contract schema work rather than assumed safe (§2.2).
4. **G-1 — no automated enforcement of any invariant above against the shipping app.** Every "Closed" verdict in this document is closed by code structure and review, not by a fitness test that would catch a regression. The 40-test suite that would do this scans the retired Rust tree, not `native/*.swift`, and its CI job is disabled. This is the single most load-bearing caveat in this entire document: treat every "SHIPPED"/"Closed" verdict above as "true today, unguarded against tomorrow" until G-1 is closed.
5. **G-2 — no crash recovery.** A user who force-quits or whose machine crashes the app gets no automatic relaunch. Not a security finding in the traditional sense, but a resilience gap worth naming here since the retired document analyzed the watchdog mechanism this gap describes the absence of.
6. **Deprovision has no remote-wipe backstop (accepted, not a defect).** Revocation is GitHub-access removal plus shared-secret-store token rotation; content already synced to a departed person's machine before revocation is not remotely erased. No MDM exists to reach the device, by design (CSE decision D4).

---

## 6. A note on scope and naming

The two retired red-team documents (`redteam-platform.md`, `redteam-use-cases.md`) predate both the product's rename from "Aviator" to "Control Tower" and the pivot from Tauri to native Swift; their finding IDs (A-C1…A-M17, B-C1…B-L3) remain the stable citation keys used above where a finding is still cited. This document does not re-litigate any finding those two documents already closed against the Tauri-era design — where a mechanism they analyzed does not exist in the shipping app, this document says so plainly rather than carrying the closure forward as if it still applied.
