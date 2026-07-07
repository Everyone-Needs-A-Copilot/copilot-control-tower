# Contributing to Copilot Control Tower

Thanks for wanting to work on Control Tower. This is a small, deliberately
restrained project — read this before you write code, especially the section
below on proposing features. Most "obvious" additions here are rejected on
purpose.

By participating, you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you propose a feature

**Read [`SOUL.md`](SOUL.md) — specifically Section 5, the Feature Filter —
before opening a feature request or a PR that adds new capability.** This is
not a formality. Control Tower's whole trust model rests on staying small, and
the project has already said "no" — in writing, with reasoning — to several
things that feel like obviously good ideas:

| "Obvious" idea | Why it's rejected |
|---|---|
| A chat surface / "ask if your machine is okay" | Violates parse-never-compute — the app renders CLI verdicts, it never reasons about your machine. See SOUL.md, "The Copilot of the Copilot." |
| An offline health score, so the icon "still works" without the CLI | Creates a second, possibly-wrong source of truth. An honest *Waiting-for-network* state is correct; a guess is not. See "The Second Pilot." |
| `KeepAlive=true` in the `launchd` plist | Resurrects a crash-looping bad build. The watchdog is crash-only (`KeepAlive={SuccessfulExit:false}`) by design. |
| `--force` / `--skip-verify`, or any "unstick it" bypass | The entire safety claim is zero bypass flags, always. See "The Convenience Backdoor." |
| Reading update-feed URLs or security config from user-editable prefs | Security-sensitive config is honored **only** from the forced/managed MDM domain — never user prefs. |
| A paid tier / hosted dashboard / enterprise SKU | Pure OSS, free forever, is a founding decision — openness *is* the security guarantee. See "The Ledger That Learns to Bill." |

If your idea survives SOUL.md's four gates (Parse-Not-Compute, Essential-Job,
Right-Actor, Trust-Surface) **and** doesn't violate any of the six invariants
in [`CLAUDE.md`](CLAUDE.md), open an issue using the feature request template
and reference which gates it passed. If it doesn't survive the filter, it's
still worth discussing as an issue — the answer may be "this belongs in the
`copilot` CLI, not in Control Tower" — but don't submit it as a PR against
this repo without that discussion first.

**The six invariants, at a glance** (full text in [`CLAUDE.md`](CLAUDE.md)):

1. **Parse, never compute.** Control Tower calls CLI verbs via a versioned
   `--json` contract and renders the result. No resolution, sync, signature,
   or wipe logic lives in the app.
2. **Single process.** One signed binary — tray + supervisor + scheduler. No
   daemon, no in-app fallback loop. `launchd` is a crash-only watchdog.
3. **Never-destroy.** The app may re-materialize disposable mirrors; it never
   touches a dirty personal working tree.
4. **Security posture is inherited and enforced, never weakened.** No
   `--skip-verify`, no `--force`. Security config is honored only from the
   forced/managed domain.
5. **Route by actor-competence × reversibility.** Auto-act on reversible
   things the user can't judge; escalate to IT what they can't action; ask the
   user only about non-deferrable decisions on their own data.
6. **One-way inheritance; secrets never travel in it.** Sync is pull-only and
   downward; secrets live in the OS keychain and/or a managed secret store,
   never in git; no cross-tier write capability from a personal-holding path.

A PR that adds resolution/sync/merge/signature logic to the app, weakens the
security posture, or reintroduces `--force`/`KeepAlive=true`/a chat surface
will be closed regardless of code quality. Raise the design question first.

## What this project is

Control Tower is a macOS menu-bar app (Tauri v2) that is a thin
**face + supervisor** over the `copilot`/`cc` CLI, plus an Admin-mode IT
deploy tool. Start with:

- [`docs/START-HERE.md`](docs/START-HERE.md) — orientation and where the
  project currently stands
- [`docs/00-overview/product-brief.md`](docs/00-overview/product-brief.md) —
  what it is and isn't
- [`docs/01-architecture/architecture.md`](docs/01-architecture/architecture.md) —
  the validated architecture (25 red-team findings mapped to fixes)
- [`docs/01-architecture/cli-contract.md`](docs/01-architecture/cli-contract.md) —
  the `--json`/`flock` contract the app depends on
- [`docs/02-prd/prd.md`](docs/02-prd/prd.md) — the parallel, multi-phase PRD
  with per-task acceptance criteria and phase gates

The UI/UX is designed via Product Creation Copilot, not hand-invented in a PR
— see [`docs/03-design/ui-ux/README.md`](docs/03-design/ui-ux/README.md)
before proposing visual/interaction changes.

## Development setup

<!-- TODO: fill in exact toolchain versions once the app scaffold exists. -->

- **Rust** (stable toolchain) + **Tauri v2** CLI (`cargo install tauri-cli`
  or the npm wrapper, per Tauri v2 docs)
- **Node.js** for the minimal web UI tooling (kept intentionally tiny — no
  heavy framework)
- Clone this repo and the sibling `copilot`/`claude-copilot` CLI repo; Control
  Tower vendors pinned, already-signed CLI binaries rather than building the
  CLI itself — see [`docs/07-contributing/README.md`](docs/07-contributing/README.md)
  for the cross-repo contract once it's written

Full dev-environment, build, signing, and self-update documentation lives in
[`docs/07-contributing/README.md`](docs/07-contributing/README.md) — check
there first; this file only summarizes the parts relevant to opening a PR.

## Build

<!-- TODO: exact commands once the Tauri scaffold lands (WS-D). -->

The expected shape, per the architecture doc:

- `tauri build` produces a universal binary (`aarch64` + `x86_64`)
- CI verifies the vendored `copilot`/`cc` CLI artifact (`codesign`, `spctl`)
  but never re-signs it
- Local and CI builds should stay at parity — if your local build diverges,
  that's a bug to report, not a workaround to script around

## Making a change

1. **Open an issue first** for anything beyond a small fix — bug fixes can go
   straight to a PR; new behavior should get a design nod first, especially
   given the feature-filter constraints above.
2. **Keep the change scoped.** One logical change per PR. If a PR touches the
   CLI contract *and* the app, split it — the CLI contract changes belong in
   the `copilot`/`claude-copilot` repo, frozen and versioned, before the app
   consumes them.
3. **Write tests.** Contract tests against the versioned `--json` schema for
   anything that parses CLI output; unit tests for Rust logic; see
   [`docs/04-validation/test-plan.md`](docs/04-validation/test-plan.md).
4. **Update docs** in the same PR — a behavior change without a doc change is
   incomplete.
5. **Run the PR checklist** in [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)
   before requesting review — it exists to catch invariant violations before
   a human has to.

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

Open a [GitHub Discussion](https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/discussions)
or [Issue](https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower/issues)
on this repo rather than emailing a maintainer directly, so the answer is
discoverable for the next contributor.
