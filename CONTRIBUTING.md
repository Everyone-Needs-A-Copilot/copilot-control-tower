# Contributing to Copilot Control Tower

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. The owner's audience priority for this project's documentation is (1) their own future self, (2) buyers/non-technical evaluators, (3) organizations considering adoption — open-source contributors submitting patches are explicitly not an optimization target. This file is kept intentionally minimal for that reason: it exists so a contribution doesn't cause harm, not to onboard a new maintainer.

Thanks for wanting to work on Control Tower. This is a small, deliberately restrained project — read this before you write code, especially the section below on proposing features. Most "obvious" additions here are rejected on purpose.

By participating, you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you propose a feature

**Read [`SOUL.md`](SOUL.md) — specifically Section 5, the Feature Filter — before opening a feature request or a PR that adds new capability.** This is not a formality. Control Tower's whole trust model rests on staying small, and the project has already said "no" — in writing, with reasoning — to several things that feel like obviously good ideas:

| "Obvious" idea | Why it's rejected |
|---|---|
| A chat surface / "ask if your machine is okay" | Violates parse-never-compute — the app renders CLI verdicts, it never reasons about your machine. See SOUL.md, "The Copilot of the Copilot." |
| An offline health score, so the icon "still works" without the CLI | Creates a second, possibly-wrong source of truth. An honest *Waiting-for-network* state is correct; a guess is not. See "The Second Pilot." |
| `KeepAlive=true` in the `launchd` plist | Resurrects a crash-looping bad build. The watchdog is crash-only (`KeepAlive={SuccessfulExit:false}`) by design — noting honestly that the shipping Swift app does not implement this watchdog yet (G-2, see `CLAUDE.md`); the rule still governs any implementation that lands. |
| `--force` / `--skip-verify`, or any "unstick it" bypass | The entire safety claim is zero bypass flags, always. See "The Convenience Backdoor." |
| Reading update-feed URLs or security config from user-editable local prefs | Security-sensitive config is honored **only** from compiled-in trust roots plus signed, inherited org/foundation config — never a local, user-editable file, env var, or CLI flag. **MDM (Jamf/Kandji/Intune) is dropped completely as a mechanism** for this product — not deferred, not a future channel. |
| A paid tier / hosted dashboard / enterprise SKU | Pure OSS, free forever, is a founding decision — openness *is* the security guarantee. See "The Ledger That Learns to Bill." |

If your idea survives SOUL.md's four gates (Parse-Not-Compute, Essential-Job, Right-Actor, Trust-Surface) **and** doesn't violate any of the six invariants in [`CLAUDE.md`](CLAUDE.md), open an issue using the feature request template and reference which gates it passed. If it doesn't survive the filter, it's still worth discussing as an issue — the answer may be "this belongs in the `copilot` CLI, not in Control Tower" — but don't submit it as a PR against this repo without that discussion first.

**The six invariants, at a glance** (full text in [`CLAUDE.md`](CLAUDE.md)):

1. **Parse, never compute.** Control Tower calls CLI verbs via a versioned `--json` contract and renders the result. No resolution, sync, signature, or wipe logic lives in the app.
2. **Single process.** One signed binary — tray + supervisor + scheduler. No daemon, no in-app fallback loop. `launchd` is meant to be a crash-only watchdog; the shipping app does not implement that watchdog today (an open, named gap — see `CLAUDE.md`).
3. **Never-destroy.** The app may re-materialize disposable mirrors; it never touches a dirty personal working tree.
4. **Security posture is inherited and enforced, never weakened.** No `--skip-verify`, no `--force`. Security-sensitive config is honored only from compiled-in trust roots plus signed, inherited org/foundation config — never from local, user-editable config. There is no MDM channel; MDM is dropped completely as a mechanism for this product.
5. **Route by actor-competence × reversibility.** Auto-act on reversible things the user can't judge; escalate to IT what they can't action; ask the user only about non-deferrable decisions on their own data.
6. **One-way inheritance; secrets never travel in it.** Sync is pull-only and downward; secrets live in the OS keychain and/or a tier-scoped shared secret store, never in git; no cross-tier write capability from a personal-holding path.

A PR that adds resolution/sync/merge/signature logic to the app, weakens the security posture, or reintroduces `--force`/`KeepAlive=true`/a chat surface will be closed regardless of code quality. Raise the design question first.

**Honest note on enforcement.** The six invariants above are architectural commitments upheld by code review and the shell-level release gates in `scripts/package-user-release.sh`, not by an automated fitness-test suite against the shipping app. A 40-test fitness suite exists in the retired Rust tree (`src-tauri/tests/fitness_*.rs`) and would enforce most of these if ported to scan `native/*.swift` and re-enabled in CI; that port has not happened. Don't cite those tests as currently gating this codebase.

## What this project is

Control Tower is a native macOS menu-bar app (SwiftUI/AppKit) that is a thin **face + supervisor** over the `copilot`/`cc` CLI, plus an Admin-mode IT deploy tool. An earlier Tauri v2/Rust plan was retired before the app shipped; that code was removed from this repository in commit `chore: remove retired src-tauri tree`; it survives only in git history. Start with:

- [`docs/START-HERE.md`](docs/START-HERE.md) — orientation and where the project currently stands
- [`docs/00-overview/product-brief.md`](docs/00-overview/product-brief.md) — what it is and isn't
- [`docs/01-architecture/architecture.md`](docs/01-architecture/architecture.md) — the current architecture against the native app
- [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md) — the `--json`/`flock` contract the app depends on
- [`docs/02-prd/prd.md`](docs/02-prd/prd.md) — what was built against the original phased plan, and what remains

The UI/UX design of record is the native design triad — [`docs/03-design/control-tower-native-experience-architecture.md`](docs/03-design/control-tower-native-experience-architecture.md), [`-interaction-spec.md`](docs/03-design/control-tower-interaction-spec.md), [`-visual-system.md`](docs/03-design/control-tower-visual-system.md) — see [`docs/03-design/ui-ux/README.md`](docs/03-design/ui-ux/README.md) before proposing visual/interaction changes.

## Development setup

- **Xcode command-line tools** (for `swiftc`) — there is no Xcode project file and no Swift Package Manager manifest for the app; the build is a direct `swiftc` invocation over an explicit file list.
- No Rust toolchain, no Node.js, and no Tauri CLI are required to build the shipping app. The retired `src-tauri/` tree is a separate, unmaintained toolchain question and is not part of the current build or release path.
- Clone this repo; Control Tower vendors a pinned, independently notarized copy of the `cc` CLI helper (`packaging/cc/cc`) rather than building the CLI itself. The CLI's own source lives in the sibling `claude-copilot` repo.

Further dev-environment, build, signing, and release documentation lives in [`docs/07-contributing/README.md`](docs/07-contributing/README.md), [`docs/07-contributing/release-and-versioning.md`](docs/07-contributing/release-and-versioning.md), and [`docs/07-contributing/publisher-release-runbook.md`](docs/07-contributing/publisher-release-runbook.md) — check there first; this file only summarizes the parts relevant to opening a PR.

## Build

The real build path, read directly from the packaging scripts:

- `bash scripts/build-user.command --build-only` compiles the User app (`Copilot Control Tower.app`) via `swiftc` over the explicit source list in that script — never a glob, so a new `.swift` file must be added to the script to be included.
- `bash scripts/build-admin.command --build-only` compiles the Admin app the same way, adding `admin.swift`/`admin-support.swift` and building with `-D CT_ADMIN_BUILD`.
- `scripts/package-user-release.sh` is the one real release pipeline: it builds via the script above, verifies the vendored `cc` helper (`verify-vendored-cc.sh`, checksum plus verify-not-resign, never re-signing someone else's binary), runs the headless smoke/acceptance harnesses in `scripts/tests/`, then signs, notarizes, staples, and produces the DMG in `dist/user-release/`.
- Local and CI builds should stay at parity — if your local build diverges, that's a bug to report, not a workaround to script around. The GitHub Actions release workflow's Rust job is currently gated behind a disabled variable and does not gate real releases; releases are cut locally today.

## Making a change

1. **Open an issue first** for anything beyond a small fix — bug fixes can go straight to a PR; new behavior should get a design nod first, especially given the feature-filter constraints above.
2. **Keep the change scoped.** One logical change per PR. If a PR touches the CLI contract *and* the app, split it — the CLI contract changes belong in the `copilot`/`claude-copilot` repo, frozen and versioned, before the app consumes them.
3. **Write tests.** For anything that parses CLI output, validate against the versioned `--json` schema in [`docs/01-architecture/schemas/`](docs/01-architecture/schemas/). The real test surface is the shell harnesses in `scripts/tests/` (smoke, headless-detect, bundle, schema-compatibility, notarization-order) plus the env-gated in-binary selftests described in `native/control-tower-tray.swift`'s `AppDelegate.applicationDidFinishLaunching` — there is no Rust test suite gating a real release today (see the honest note above).
4. **Update docs** in the same PR — a behavior change without a doc change is incomplete.
5. **Run the PR checklist** in [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md) before requesting review — it exists to catch invariant violations before a human has to.

## Where things live

| You want to... | Look here |
|---|---|
| Understand why a feature was rejected | [`SOUL.md`](SOUL.md) §5 Feature Filter (Case Law table) |
| Understand an invariant in depth | [`CLAUDE.md`](CLAUDE.md) + the architecture doc it links to |
| Change the CLI `--json` contract | The `copilot`/`claude-copilot` repo, not this one — see [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md) |
| Propose a UI/UX change | [`docs/03-design/ui-ux/README.md`](docs/03-design/ui-ux/README.md) |
| Report a security concern | See [`docs/05-security/security-and-trust.md`](docs/05-security/security-and-trust.md); do not open a public issue for a live vulnerability — use a private report if a security contact is published, otherwise flag it clearly as sensitive in the issue title |
| Set up your dev environment | [`docs/07-contributing/README.md`](docs/07-contributing/README.md) |

## Questions

Open a [GitHub Discussion](https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/discussions) or [Issue](https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/issues) on this repo rather than emailing a maintainer directly, so the answer is discoverable for the next contributor.
