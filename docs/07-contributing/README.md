# Contributing — developer guide

> **Status: skeleton.** The app doesn't exist yet (see
> [`../START-HERE.md`](../START-HERE.md)), so exact commands, toolchain
> versions, and CI job names below are marked `<!-- TODO -->` until WS-D (the
> build/signing/release workstream in [`../02-prd/prd.md`](../02-prd/prd.md))
> lands the scaffold. What *is* fixed — the process model, the cross-repo
> contract, the signing order, the versioning rules — is documented here now
> so the scaffold is built against a settled shape, not improvised.

For the contribution **process** (how to open an issue/PR, the invariant
checklist, and — critically — the Feature Filter you must run any new
capability through before proposing it), see
**[`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)** at the repo root. This
page is the technical companion: what you need installed, how the build
actually works, and how releases are versioned.

## 1. Dev environment

<!-- TODO: pin exact versions once the Tauri scaffold is committed. -->

| Tool | Why | Notes |
|---|---|---|
| Rust (stable toolchain) | The Tauri core — all app logic (CLI invocation, status parsing, scheduler, watchdog glue) lives here | <!-- TODO: MSRV --> |
| Tauri v2 CLI | Scaffolding, dev server, bundling | Single-process model (invariant #2) — there's no separate daemon process to run or mock locally |
| Node.js + package manager | The frontend tooling for the **minimal** web UI | Deliberately tiny — no heavy framework (design principle 3, "as little app as possible"); do not introduce one in a PR |
| Xcode command line tools | `codesign`, `notarytool`, `stapler` for local signing verification | macOS-only; see §4 |
| The `copilot`/`cc` CLI, built from `claude-copilot` | Control Tower supervises it, and dev/test needs a real binary to invoke against — see §2 | Vendored at a pinned SHA+version, never built from this repo |

Clone this repo and, separately, the `claude-copilot` repo (source of the
`copilot`/`cc` CLI). Control Tower never builds the CLI itself; it invokes an
already-built binary — see §2.

## 2. The cross-repo binary contract

Control Tower and the `copilot`/`cc` CLI are **separate repos, separate
release cadences, one consumption contract**:

- The `claude-copilot` repo's CI builds, signs, and notarizes `copilot`/`cc`
  and publishes the artifact at a **pinned SHA + version**.
- Control Tower **vendors** that already-signed artifact. Its own CI
  **verifies** the vendored binary (`codesign --verify`, `spctl --assess`) —
  it **never re-signs** it. Re-signing a CLI you didn't build would break the
  chain of custody the whole trust model depends on.
- Control Tower invokes the CLI by **absolute, translocation-safe path** —
  never the bare `copilot` command, which collides with `gh copilot`. See
  [`../01-architecture/cli-contract.md`](../01-architecture/cli-contract.md)
  for the exact invocation and `--json` schema contract.
- A **compat-floor check** in Control Tower CI blocks release if the vendored
  CLI's `schema_version` is older than the range the app declares support
  for. See
  [`release-and-versioning.md`](release-and-versioning.md) §1.3 for the full
  compat-matrix mechanics (`controltower.compat.json`) and the "a newer CLI
  pulls a newer Control Tower release, never the reverse" rule.

**What this means for local dev:** you cannot meaningfully run or test
Control Tower against a CLI you hand-built with unrelated changes — pull the
pinned version the current `main` expects, or coordinate a CLI-side change
through `claude-copilot` first (per the invariant: schema/contract changes
belong there, frozen and versioned, before this app consumes them).

## 3. Build

<!-- TODO: exact CI job names and local build commands once WS-D lands. -->

Expected shape, per [`../01-architecture/architecture.md`](../01-architecture/architecture.md)
and [`release-and-versioning.md`](release-and-versioning.md):

- `tauri build` produces a **universal binary** (`aarch64` + `x86_64`), one
  process containing tray + supervisor + scheduler (invariant #2 — no
  separate daemon to build or launch).
- Local and CI builds are expected to stay at parity; a local-only build
  quirk is a bug, not a workaround to script around.
- The build never embeds a hand-built copy of the `copilot`/`cc` CLI — only
  the vendored, pinned, pre-signed artifact from §2.

## 4. Signing, notarization & self-update

Full mechanics live in
[`../03-design/design-distribution.md`](../03-design/design-distribution.md)
(§1, §4) and [`release-and-versioning.md`](release-and-versioning.md) §2; the
summary a contributor needs:

- **Developer ID signing** in the inside-out order (innermost frameworks/
  helpers first, the `.app` last), hardened runtime on.
- **Notarization** via `notarytool submit --wait`, then **stapling** both the
  `.app` and the `.dmg` — stapling matters because the crash-only watchdog
  verifies a staged self-update bundle is stapled **offline**, before
  promoting it, so air-gapped/proxy fleets on an internal update mirror stay
  safe to auto-update without reaching Apple's CDN at swap time.
- **The update manifest is minisign-signed**, held in a **separate custody**
  from the Developer ID certificate — a single popped key must not be
  sufficient to promote a release. <!-- TODO: who holds the second key — an
  open decision tracked in the architecture doc, not yet resolved. -->
- **No bypass path exists anywhere in this chain.** No `--skip-verify`, no
  `--force`, no lower-bar signing mode "for testing" that could leak into a
  real build — see invariant #4 and `CONTRIBUTING.md`'s "Before you propose a
  feature" section.
- Rollback is a property of the **watchdog**, not the new bundle: no early
  liveness heartbeat after a staged self-update ⇒ automatic rollback to the
  last-known-good version, which is then marked poisoned on that channel. See
  [`release-and-versioning.md`](release-and-versioning.md) §5.

## 5. Release process & versioning

**[`release-and-versioning.md`](release-and-versioning.md) is the canonical
policy** — read it before cutting a release or touching anything that moves
the `--json` schema version. It covers, in full:

- Semver rules for the **app binary** vs. the **`--json` contract**
  (`schema_version`) — two independent surfaces, each with its own MAJOR/
  MINOR/PATCH triggers.
- The app↔CLI **compat matrix** (`controltower.compat.json`) and publication
  order.
- **Release channels** (`stable`, `beta`, `pinned:<version>`), gated only by
  forced-domain managed keys (`UpdateFeedURL`, `AllowSelfUpdate`,
  `UpdateChannel`) — never user-domain preferences.
- **Changelog conventions** (schema-version movement, security-fix
  cross-references, compat-matrix changes, deprecation announcements).
- **Deprecation policy** — the never-break-a-running-fleet rule, and why
  security-relevant fields can never be soft-deprecated by omission.

## 6. Where to go next

| You want to... | Read |
|---|---|
| Understand the process/contract model in full | [`../01-architecture/architecture.md`](../01-architecture/architecture.md), [`../01-architecture/cli-contract.md`](../01-architecture/cli-contract.md) |
| Know what a PR must not do before you write it | [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) and [`../../SOUL.md`](../../SOUL.md) §5 |
| Cut or review a release | [`release-and-versioning.md`](release-and-versioning.md) |
| Understand the security/trust model this build chain exists to satisfy | [`../05-security/security-and-trust.md`](../05-security/security-and-trust.md), [`../05-security/threat-model.md`](../05-security/threat-model.md) |
| See the signing/distribution design in full detail | [`../03-design/design-distribution.md`](../03-design/design-distribution.md) |

## Cross-links

[`../03-design/design-distribution.md`](../03-design/design-distribution.md)
remains the detailed design source for signing, packaging, and lifecycle —
this page and `release-and-versioning.md` are the contributor-facing
translation of it into a runnable workflow and a versioning policy,
respectively.
