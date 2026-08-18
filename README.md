# Copilot Control Tower

> **Status line — prepared for the 2026-08-12 release.** Version: **v0.6.9** (build **36**), the native SwiftUI/AppKit release that writes one Python-authored Sites-level project work order, opens a plain Terminal at that projects folder, and lets the person start and control one Claude Code or Codex conversation themselves. Python independently verifies every project and remains the only completion authority. The bundle requires and carries exactly `cc 2.10.2`, and the User app carries a per-user crash-only LaunchAgent. See [`CHANGELOG.md`](CHANGELOG.md) for the exact contract, safety, and rollback notes.

**The always-on menu-bar client + open-source IT setup/deploy tool for the Copilot ecosystem — the technical superpowers of a deeply skilled engineer, in the hands of someone who has never opened a terminal.**

Copilot Control Tower is two faces over one native macOS app: a menu-bar companion that keeps a person's Copilot environment synced and healthy without them ever touching a CLI, and an Admin tool that lets an organization stand up that same ecosystem for its whole team. The name is the model: a control tower doesn't fly the plane — it watches every flight, keeps them coordinated and on schedule, clears them to proceed, and raises the alarm when something's off.

## Who this is for

- **A non-technical person adopting Copilot.** You double-click a signed app, sign in with GitHub, and everything you're entitled to — the shared knowledge base, the CLI integrations, the Claude/Codex instruction layers your org and department have set up — appears on your machine and stays current, automatically, in the background. You never see YAML, a terminal, or a merge conflict.
- **An organization evaluating whether to adopt this.** Control Tower is how the essence of the Copilot ecosystem — "give a technical person's AI superpowers to a non-technical person's hands, safely enough to run unattended" — actually reaches your people's machines. Standing it up for your org is an Admin-mode job (repo/team scaffolding, a shared secret store, a signed capability policy), not an engineering project.
- **The owner's future self / anyone picking this codebase back up.** This README, `CLAUDE.md`, and `docs/START-HERE.md` are written to be re-entered cold. Read `docs/START-HERE.md` next.

Not a target audience: open-source contributors looking to submit patches, or a developer expecting a handoff document. `CONTRIBUTING.md` stays deliberately minimal for that reason.

## Current status: DOGFOODING

Control Tower is **running in production on one real organization (ENAC)** — not a demo, not a pilot with seed data. Phase 7 of the self-onboarding initiative reached **16/16 live apply**: every one of the sixteen component-times-tier combinations (Knowledge / CLI / Claude / Codex × foundation / org / department / personal) materializes correctly on a real machine against real GitHub repositories. It has not yet been offered to a second, outside organization. Two things remain before it is: the **V-5 cold-laptop proof** (a two-machine onboarding run against an empty keychain, proving the experience holds for someone who isn't the owner) and the **publicize step** (making the supporting `knowledge-copilot`/`cli-copilot` foundation repos public, gated on a credential rotation their prior private-repo history requires). Neither claim of "general availability" nor "the build has not started" is accurate — both have been true statements about this product at different points in its history, and neither is true today.

## What actually ships

Three native executables, built by `swiftc` from a shared ~22,600-line Swift source tree in [`native/`](native/) — there is no other UI framework in the shipping product:

| App | What it is |
|---|---|
| **Copilot Control Tower.app** | The end-user face: a menu-bar tray, a first-run wizard, and a Settings window. This is what a non-technical person runs. |
| **Copilot Control Tower Admin.app** | The same tray/wizard/Settings surface plus a 16-screen Admin mode for an org's setup owner — seed authoring, repository and team scaffolding, secret-store connection, and governance (departments, offboarding, analytics). |
| **Publisher Setup.app** | Owner-only release tooling: signing identity selection, notarization, and the build/handoff pipeline that produces the signed DMGs in [`release/`](release/). |

The real user surface, in the product's own vocabulary:

- **The tray** — a 12-state badge vocabulary (pass, ring, key, update, triangle, wrench, clock, cloud-slash, bang, spinner, hollow, none) on a single 300-second poll, plus refresh on launch and on popover open. Actions: Sync now, What changed, Settings, Quit (Admin builds add Open Administration).
- **The first-run wizard** — nine stages: Welcome, Connect GitHub, Detect, What you're getting, Departments, Your connections, Your projects, Set up, Verify.
- **Your projects** — starts with every Python-authorized new setup and correction selected. Control Tower writes one work order for the complete selected batch, opens a normal Terminal at the projects folder, and shows one short prompt to paste after the person starts Claude Code or Codex themselves. The person owns that one conversation; Python remains the only verifier.
- **Settings** — four components (Knowledge Copilot, CLI Copilot, Claude Copilot, Codex Copilot) across four tiers (foundation, organization, department, personal), plus a project list and a connections card.
- **Admin mode** — 16 surfaces across an 11-stage onboarding flow (orientation through done) and a 5-stage governance flow (add a department, someone left, connect the shared store, org setup, analytics), driven by a deterministic bash engine (`scripts/admin_bootstrap.sh`), never by the app computing org state itself.

## The one invariant — and its honest gap

**Control Tower parses; it never computes.** Every health verdict, resolution, signature check, and materialize decision is done by the `copilot`/`cc` CLI over a versioned `--json` contract — the same pipeline a headless developer would run by hand. If Control Tower vanished, the CLI would still be correct.

This and the five other invariants in [`CLAUDE.md`](CLAUDE.md) are architectural commitments, upheld today by code review and the shell-level release gates in `scripts/package-user-release.sh` — **not** by automated fitness tests against the shipping app. The 40 `fitness_*.rs` tests that were written to enforce them all scan the retired Rust tree (`src-tauri/src/`), cannot see a single line of the shipping Swift, and the CI job that runs them is disabled. Porting that suite to the native app is a known, open item, not a hidden defect. Invariant #2's `launchd` crash-only watchdog is the same story: it is a stated design position and exists as packaging assets in the retired Rust tree, but the shipping Swift app does not install or manage it today. Neither gap is fixed by this documentation pass — it is named so the next person doesn't have to rediscover it.

## Tech

- **Native macOS SwiftUI/AppKit**, one signed binary per face, macOS-only. This supersedes an earlier Tauri v2/Rust-core plan.
- The retired Tauri v2 source tree (`src-tauri/`) was removed from this repository in commit `chore: remove retired src-tauri tree`; it survives only in git history. It was never built, never part of any release, and does not describe the current app.
- Windows was designed against under the retired Rust core and is now formally out of scope; see the superseded banner on [`docs/01-architecture/windows-parity.md`](docs/01-architecture/windows-parity.md).
- A vendored, independently notarized copy of the `cc` CLI helper ships inside each app bundle (`Contents/Resources/cc`) and is preferred over any machine-installed copy.
- Developer ID signed, hardened runtime, notarized and stapled. Signing identity: `Developer ID Application: Pablo Alejo Jr (3SYGVX2HB8)`. Signed releases and their provenance are retained under [`release/`](release/).

## Release integrity

[`scripts/package-user-release`](scripts/package-user-release) is an inert adapter to the separately installed Publisher Bootstrap trust anchor. The root-owned, Developer-ID-signed, notarized, and stapled anchor under the root-only `/Library/PrivilegedHelperTools` trust root resolves an operator-approved immutable ref from this exact canonical HTTPS repository, fetches it into a config-isolated bare Git store, materializes a source tree with no `.git` directory, and repeatedly verifies the materialized bytes before making release authority available. Repository source cannot install or self-authorize an anchor merely by rebuilding itself. Its publisher preparation command is permanently credential-free: it emits only unsigned review inputs and an intentionally incomplete external-approval manifest template. First installation remains hard-blocked until an independently controlled Installer signing context, out-of-band exact tuple, root-owned staging transaction, and monotonic version floor are present.

Building, signing, notarizing, and stapling a candidate does not publish it. Publishing a release is a separate owner-gated action.

## Building from a tag

`v0.6.9` is the only tag that builds correctly. Its `packaging/cc/cc` is the real signed, notarized CLI and matches the `packaging/cc/PINNED_SHA256` recorded beside it; `scripts/verify-vendored-cc.sh packaging/cc/cc` confirms the checksum, the upstream Developer ID signature, and its Designated Requirement.

Every tag before `v0.6.9` carries a 1342-byte placeholder at that path instead. A history rewrite that stripped blobs over 5 MB removed all committed revisions of the binary, and because git-filter-repo rewrites an incremental stream, the path inherited an early placeholder rather than disappearing. Those binaries were signed and notarized, so they cannot be rebuilt byte-identically to satisfy the `PINNED_SHA256` each of those tags records. Building an older tag would produce an app bundling the placeholder — don't ship one. Build from `v0.6.9` or from `main`.

## Read next

| Doc | What |
|---|---|
| [`docs/START-HERE.md`](docs/START-HERE.md) | Orientation for a fresh session |
| [`docs/01-architecture/architecture.md`](docs/01-architecture/architecture.md) | The current architecture — native app, CLI contract, honest invariant status |
| [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md) | The `copilot --json` verb contract the app actually calls |
| [`docs/02-prd/prd.md`](docs/02-prd/prd.md) | What was built, against the original phased plan, and what remains |
| [`docs/03-design/ui-ux/README.md`](docs/03-design/ui-ux/README.md) | The design of record for the native app |
| [`CHANGELOG.md`](CHANGELOG.md) | The real, dated release history |

## Ecosystem context

Control Tower is a client of the Copilot Solutioning Ecosystem. Self-contained copies of the relevant ecosystem docs live in [`docs/10-reference/`](docs/10-reference/) (the four-tier topology, the use cases the app delivers, the CSE alignment decisions this repo conforms to).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
