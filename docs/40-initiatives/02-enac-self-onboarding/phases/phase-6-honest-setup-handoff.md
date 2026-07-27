# Phase 6a — Honest setup: Holding, adoption, and organization sign-in (handoff)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-6-ecosystem-install-and-onboarding-proof.md`](phase-6-ecosystem-install-and-onboarding-proof.md).
> Companion document: [`phase-6-honest-setup-work-record.md`](phase-6-honest-setup-work-record.md) — what was wrong, what changed, and why, organized by problem rather than by commit. Read that first for context; this document is the pickup: state, blockers, open decisions, known gaps, and how to verify and resume.
> **Taking this over cold?** Nothing here is merged or pushed. Read this document end-to-end before touching either repo, then run the verification commands in §6 yourself before trusting any number quoted below, including this document's own.

## 1. State

Both branches are unmerged and unpushed. The original handoff was documentation-only; TASK-161 and TASK-162 now add the safety implementation, verification coverage, and completion record described below.

| Repo | Branch | Ahead of | Pushed? | Tip commit |
|---|---|---|---|---|
| `copilot-control-tower` | `app-build` | `origin/app-build` by 23 commits | Not pushed | This TASK-161/TASK-162 commit |
| `claude-copilot` | `feat/adopt-and-project-setup` | local `main` by 7 commits | No remote branch exists at all (`git ls-remote --heads origin feat/adopt-and-project-setup` returns nothing) | `8fedac6` |

**Both native app targets build clean.** Verified by running `scripts/tests/smoke-scenarios.sh`, which builds both bundles via `scripts/build-user.command --build-only` and `scripts/build-admin.command --build-only` before running any scenario; both build steps exited 0. Note for future builds: **you do not need to set `CC`/`PATH` yourself** — `scripts/build-user.command:68` and `scripts/build-admin.command:80` already hardcode `CC=/usr/bin/cc PATH=/usr/bin:$PATH` immediately before their own `swiftc` invocation, precisely because the `copilot` CLI installs itself as `cc` on this machine and shadows the real C compiler. That protection is already baked into the scripts; it only matters if you invoke `swiftc`/`swift build` directly, outside them.

**Test counts, verified by me, this session, from a clean invocation of each suite** (not re-derived from commit messages):

| Suite | Command | Result |
|---|---|---|
| App smoke scenarios | `bash scripts/tests/smoke-scenarios.sh` (from repo root) | **110 passed, 0 failed** — matches the commit-message figure exactly. |
| App admin bootstrap suite | `bash scripts/tests/test_admin_bootstrap.sh` | **214 passed, 0 failed** — includes read-only verification of the public bootstrap repository and exact two-field file contract. |
| CLI focused safety suite | `cd claude-copilot/tools/cc && source .venv/bin/activate && pytest tests/test_ssh_identity.py tests/test_onboard_contract.py -o addopts=''` | **50 passed, 0 failed**. |
| CLI full pytest suite | `cd claude-copilot/tools/cc && source .venv/bin/activate && pytest -o addopts=''` | **1,104 passed, 3 failed, 14 errors, 0 skipped** (1,121 collected). |

**The CLI number does not match the commit messages' self-reported "1,100 passing, 14 skipped", and I'm flagging that rather than quietly reporting the commit figure.** I traced the discrepancy rather than assuming either number was wrong:

- The 3 failures are all in `tests/test_fts5_integration.py::TestCrossToolContract`, each failing with `ModuleNotFoundError: No module named 'tc'`. That test imports a sibling package, `tc.db.fts5_core` — this machine's separate Task Copilot CLI (`/opt/homebrew/bin/tc`), not something `cc`'s own `pyproject.toml` declares as a dependency anywhere. This `.venv` is scoped to `tools/cc` only, so `tc` was never on its `sys.path`.
- The 14 errors are all in `tests/test_mcp.py::TestMcpToolSchemas`, each failing with `AttributeError: 'Server' object has no attribute '_list_tools_handler'`. That test class has its own guard for exactly this situation — `tests/test_mcp.py:144`, `pytest.skip("mcp package not installed — schema tests skipped")` — but the guard only fires when `import mcp` itself fails. In this `.venv`, `mcp` **is** installed (an optional extra, `pip install -e ".[mcp]"` or `.[dev]"`-adjacent), so the guard doesn't fire, and the test proceeds to call a private attribute (`server._tool_handlers`/`_list_tools_handler`) that the installed `mcp` package version no longer exposes.
- Both `tests/test_mcp.py` and `tests/test_fts5_integration.py` last changed **2026-06-17** (`git log -1 -- <path>`), over a month before any of the four commits in this sub-phase, and neither file is touched by any of their diffs. **This is pre-existing environment coupling, not a regression from `e3e1826`/`8efe9ad`/`44fcfa5`/`20886b3`.** My best reconstruction: the environment the commit messages' own counts came from either didn't have the `mcp` extra installed (so those 14 tests skipped cleanly, matching "14 skipped") or ran in a combined workspace where a sibling `tc` install made the cross-tool test pass too — in either case, a different venv than the one at `claude-copilot/tools/cc/.venv` that exists on this machine right now.
- **Recommendation, not acted on** (out of scope for a read-only documentation pass): either (a) uninstall/avoid the `mcp` extra in this venv to reproduce the historical 14-skipped baseline exactly, and don't worry about the `tc` sibling gap since it was apparently already a known-environment-dependent 3 failures, or (b) fix both properly — guard `test_mcp.py`'s schema tests behind the actual API surface still present in whatever `mcp` version is pinned, and give `test_fts5_integration.py`'s cross-tool test the same `pytest.importorskip("tc", ...)`-style guard `test_mcp.py` already uses for `mcp`, so a `cc`-only venv doesn't fail a test that was never meant to run there.

**Config/secrets integrity, verified before and after every run in this session** (see §6 for the exact commands):

| Path | SHA-256 before | SHA-256 after | Changed? |
|---|---|---|---|
| `~/.claude/cc/config.json` | `604ad20169016fc258551579bc8fc787876eb143504ad901ddf8f54a210cd30d` | `c4cdf9cb7a26aa9fb2d2a4cc787bcc5e2a2644b7f583e2a4803a07c88d228bf8` | **Yes, intentionally:** the live standup wrote `github_app.org: Everyone-Needs-A-Copilot` after publication. The full CLI test run itself left the before hash unchanged. |
| `~/.ssh/config` | `3afe60267212ab03742a784beeff4a402e3fa7b3016b4a5a84a0ac750b0d0385` | `3afe60267212ab03742a784beeff4a402e3fa7b3016b4a5a84a0ac750b0d0385` | No |
| `~/.config/copilot/copilot.layers.yml` | `9fea06b6498ebf941a3c7fff0e720aa041d93e0acedac929bdaea5c5dbe16038` | `9fea06b6498ebf941a3c7fff0e720aa041d93e0acedac929bdaea5c5dbe16038` | No |
| `~/.claude/memory/` (tree hash) | `db5bdcf4003a6e1aeca09977e7817079cfdb589f830fe8a9a9147328143c201f` | `db5bdcf4003a6e1aeca09977e7817079cfdb589f830fe8a9a9147328143c201f` | No |
| `~/Library/Application Support/CopilotControlTower/standup-brief.{json,md}` | mtime `Jul 27 10:20:09`, before any test run this session | unchanged (not touched by the smoke or bootstrap suites, which use an isolated `$TMPDIR/ct-smoke-scenario-home.*` `HOME` override) | No |

I did not run `gh auth refresh` or any `--apply` flag. The owner-authorized live standup did invoke its existing local-pointer step, which is the intentional `cc config set github_app.org Everyone-Needs-A-Copilot` mutation recorded above.

---

## 2. The owner action is complete

Nothing in this sub-phase (or in Phase 6 generally) works for a real, first-time end user until the organization publishes a public repository, **`Everyone-Needs-A-Copilot/copilot-bootstrap`**, containing exactly one file, `bootstrap.yml`:

```yaml
org: Everyone-Needs-A-Copilot
github_app:
  client_id: "Ov23li2VmVUyOGXbwyDX"
```

Both values are non-secret by ratification: a GitHub organization name is public, and a GitHub OAuth/App **client id** is meant to be public (only the client *secret* is sensitive, and it is never collected anywhere in this flow). I confirmed both values are already correct and present in this machine's own local admin state — `~/Library/Application Support/CopilotControlTower/standup-brief.json`'s `org` and `github_app.client_id` fields match the two lines above exactly.

**Published 2026-07-27 under TASK-162.** The owner-authorized standup created [`Everyone-Needs-A-Copilot/copilot-bootstrap`](https://github.com/Everyone-Needs-A-Copilot/copilot-bootstrap) as a public repository, wrote the exact file above, and set this Mac's local organization pointer. Every pre-existing organization and department artifact was reported `already-present` or `skipped`; only the public repository, `bootstrap.yml`, and local pointer changed.

**Why it mattered:** without this public file, `cc auth login` could not resolve which GitHub App to start a device-flow sign-in against on a Mac that had never signed in before. That signed-out discovery deadlock is now removed; the remaining clean-machine proof can exercise the real path.

The verification gap was closed before publication: `--verify --json` now checks public visibility and compares `bootstrap.yml` byte-for-byte with the two-field rendering. Before the live run those rows were the only failures (`must_fix: 2`, `unknown: 0`); afterward both passed and the full summary was `must_fix: 0`, `unknown: 0`. An unauthenticated `curl` to the raw URL returned exactly the YAML above.

**Repeatable verification:**

1. Run `bash scripts/admin_bootstrap.sh --verify --json`; confirm both `bootstrap-*` rows pass and the summary is `must_fix: 0`, `unknown: 0`.
2. Run `curl -fsSL https://raw.githubusercontent.com/Everyone-Needs-A-Copilot/copilot-bootstrap/main/bootstrap.yml` without a GitHub token; confirm the exact YAML above.

---

## 3. Open decisions requiring a human

**3.1 — `cc auth grant` is unbuilt; the earlier policy fork was framed from the wrong app type.** H7 (the wizard variant that tells someone their GitHub sign-in cannot register this Mac's key) degrades to the documented `gh auth refresh` command because the verb that would drive its button does not exist. The architecture and runbooks consistently define the current organization-owned identity as an **OAuth App**, not a GitHub App, and GitHub's device-code endpoint accepts OAuth scopes. GitHub's current REST contract requires `write:public_key` to list/create a user's SSH key; `admin:public_key` is broader and is only needed for full management such as deletion.

The least-privilege recommendation is therefore to reuse the existing organization-owned OAuth App, request `write:public_key` in the grant device flow, validate that the returned identity matches the signed-in user, replace that user's Keychain token only after successful validation, and have the CLI call the keys API with its own Keychain token. This also closes a second architectural mismatch: today's SSH code shells out to `gh api`, so granting the organization's OAuth token would otherwise leave the actual registration call using `gh`'s still-unprivileged token.

This recommendation still needs owner ratification before implementation because it expands the permissions of the product's existing sign-in identity. Borrowing GitHub CLI's client identity or creating a second OAuth App are no longer the default options; both add an identity boundary without a technical necessity. Until ratification, every H7 screen continues to show the command fallback and never a button that does nothing.

**3.2 — `cc config set` has no `--json` output.** `docs/01-architecture/schemas/auth.schema.json` and `docs/03-design/control-tower-copy-deck.md` Appendix E.4 both flag this as open: the organization-question screen (§2.1.1) persists the org-name pointer via `cc config set github_app.org <name>`, and the CLI's own `commands/auth.py` docstring already names this as the app's job. But `cc config set` prints human-readable text and returns only an exit code — no structured payload the app can parse under invariant #1's versioned-contract discipline. The copy itself does not depend on the answer (no string claims the value was saved; the one failure path routes to an existing, honest H2 screen), but the **contract** question is real: is exit-code-only acceptable for a mutating verb under the versioned `--json` contract, or does persistence need a proper machine-readable verb of its own? This is a repo-architecture call (WS-A contract shape), not something to resolve by precedent-matching in isolation.

---

## 4. Known gaps, stated plainly

**Closed on 2026-07-27 — the GUI test-harness and first visual-pass gap.**
`CT_VISUAL_TEST_BUILD=1` now compiles a test-only `CT_VISUAL_SCENARIO`
loader into the native User app. It drives the real model and render paths for
all seven Holding variants, the adoption offer, the completion fallback, and
the organization question without depending on device-flow or network timing.
The complete matrix was captured at 1640×1408 and inspected on real pixels.
The organization question and adoption flow were also inspected in the exact
notarized release candidate, not only the development build. The ordinary
production build recompiles when the build mode changes, and
`scripts/tests/test_user_app_bundle.sh` fails if the visual hook or its
test-only symbols are present in the production executable.

**`permissionNeededPending` and `reopenForConnectionOffer()`/`reopenForPermissionNeeded()` are implemented and wired, not merely designed.** `native/control-tower-tray.swift` derives both booleans live from the same read-only `ecosystemOnboardPlan` refresh the tray already performs (lines ~303–370), renders a Region 6 prompt/notice pair from them (~1109, ~1211), and each button calls into `WizardWindowController.shared.reopenForConnectionOffer()` / `.reopenForPermissionNeeded()` (`native/wizard.swift:5197`, `:5226`) to reopen the wizard directly onto the relevant screen. This closes the gap the `9d4730f` commit message itself flagged as "unwired." Scenarios S24–S26 keep the routing logic covered, and the destination adoption and permission screens are now included in the real-pixel matrix above. Clicking through from the tray prompt remains part of the fresh-account proof rather than a release-code gap.

**The `copilotcontroltower://connect?organization=` deep link was designed, then deliberately dropped — not forgotten.** It would let the organization's download page hand the org name to the app directly, removing the one paste this whole sub-phase's fallback screen exists to handle. Reasoning recorded in `docs/03-design/control-tower-copy-deck.md` §2.1.1 and `docs/03-design/landing-site.md` §3.1: a custom URL scheme registers a handler any process on the machine can invoke, on the one code path that runs before any credential exists, and to stay safe it would still need a confirmation screen anyway — so it buys one saved paste at the cost of new, externally-triggerable attack surface. The copyable name on the download page carries nearly all the same benefit with none of the risk. Revisit once the organization-question flow has real usage and the saved paste is worth re-litigating the surface.

**Closed in TASK-161 — the layer-manifest test-isolation gap.** `build_ecosystem_onboard_report` defaults to the real `~/.config/copilot/copilot.layers.yml` when a caller omits `manifest_path`; two legacy locations can also be adopted. The aggregate YAML writer now calls `assert_write_is_isolated` before `mkdir`, temporary-file creation, or replacement; all three real paths are in `_FORBIDDEN_REAL_PATHS`; and the global autouse fixture checksums all three before and after every test. A focused regression proves each path fails before any artifact is created or replaced.

**Closed in TASK-161 — the passphrase-less SSH happy path.** The inherited implementation used `ssh-keygen ... -N ""`, producing a bare private-key file while later claiming Keychain-backed protection. The corrected path generates a high-entropy per-machine passphrase, creates a bcrypt-PBKDF-protected OpenSSH key, loads it with `ssh-add --apple-use-keychain`, and removes a just-created keypair if secure agent enrollment fails. The normative security document now states the platform behavior precisely: macOS Keychain stores the passphrase, not the private key; the durable private-key file remains encrypted. Existing passphrase-less keys from builds predating this fix are not silently rotated because that changes a live GitHub identity; an explicit migration/rotation transaction remains follow-up work.

---

## 5. Two incidents worth recording as process lessons

Both are closed. Both are recorded here as lessons about the *shape* of the failure, not as confessions — the generalizable point is that a test suite with no injectable root will eventually edit a developer's real machine, and detection-after-the-fact is not sufficient when the failure mode is silence.

**Incident 1 (2026-07-25, closed in `44fcfa5`): a pytest tmpdir landed in the live `~/.claude/cc/config.json`.** An onboard test passed a manifest path through to `write_config()` without stubbing it, and `machine_config_path()` resolved `Path.home()` with no override seam at all. The test run edited the real config file and left a pytest tmp-directory path sitting in it — undetected until someone went looking. Root cause closed by adding an injectable `CC_MACHINE_ROOT` environment-variable seam (`config_paths.py`), applied automatically by an autouse fixture in `tests/conftest.py`, plus a before/after checksum of the real file that fails the whole run if it moved.

**Incident 2 (2026-07-27, closed in `20886b3`): a real `cc config set github_app.org` ran during a bootstrap test.** This one is more instructive, because it happened *while closing the first incident's own class of bug*: a reviewer demonstrated that the checksum-only detection from Incident 1 could itself be defeated — a probe that cleared the `CC_MACHINE_ROOT` override and called the write path directly still wrote to the real config, with only the teardown checksum noticing, after the fact. For a failure whose entire danger is silence, noticing afterward is not enough. Root cause closed by adding a `write_guard` module (`core/write_guard.py`) that hard-refuses, **at the moment of the write itself**, any path resolving to or inside a fixed denylist of real cc locations, gated on pytest's own `PYTEST_CURRENT_TEST` sentinel — a much sturdier signal than an environment variable a test could separately monkeypatch around. The same commit gave the global memory root the equivalent `CC_GLOBAL_MEMORY_ROOT` seam, closing a second, structurally identical gap that `44fcfa5` had flagged but not yet fixed. Both were verified byte-identical (config, SSH config, and memory store) before and after the full suite in the commit that closed them.

Both root causes are closed for the paths they cover. §4 above records the one path (the layer manifest) this documentation pass found that the same denylist does not yet cover.

---

## 6. How to verify you haven't broken it

Run these from each repo's root. Do not skip the checksum steps — they are the only thing standing between "the suite passed" and "the suite passed without touching a real file."

**App repo (`copilot-control-tower`):**

```bash
# Smoke scenarios (builds both native targets first; CC/PATH are already
# handled inside the build scripts themselves, see §1 — no need to set them
# here, but harmless if you do).
bash scripts/tests/smoke-scenarios.sh
# Expect: "=== smoke-scenarios: 110 passed, 0 failed ===" and
# "smoke-scenarios.sh: PASS"

# Admin bootstrap offline harness (fully mocked gh; nothing touches real GitHub).
bash scripts/tests/test_admin_bootstrap.sh
# Expect: "admin_bootstrap tests: 214 passed, 0 failed"
```

**CLI repo (`claude-copilot/tools/cc`):**

```bash
cd /Volumes/Dev/Sites/COPILOT/claude-copilot/tools/cc

# Checksum the real machine state BEFORE, so you can prove nothing moved.
shasum -a 256 "$HOME/.claude/cc/config.json" "$HOME/.ssh/config"

# Activate the venv rather than overriding PATH yourself: the venv's own
# bin/cc is the editable-install shim the suite expects `cc` to resolve to.
# (Unlike the app repo's Swift build, do NOT prefix this with
# `CC=/usr/bin/cc PATH=/usr/bin:$PATH` — that PATH override resolves `cc` to
# the real C compiler instead of the venv's own shim and breaks every test
# that shells out to `cc env`/`cc config list`, which is a different failure
# mode than the one that prefix exists to prevent in the app repo's cargo/
# swiftc build.)
source .venv/bin/activate
pytest
# Expect (as of this session, verified): 1,104 passed, 3 failed, 14 errors,
# 0 skipped — see §1 for exactly why this differs from the commit messages'
# quoted "1,100 passing, 14 skipped", and confirm the 3 failures are still
# only in test_fts5_integration.py::TestCrossToolContract and the 14 errors
# only in test_mcp.py::TestMcpToolSchemas before concluding nothing regressed.

# Checksum again AFTER. Both lines must be byte-identical to the BEFORE run.
shasum -a 256 "$HOME/.claude/cc/config.json" "$HOME/.ssh/config"
```

**Two pytest-invocation traps, both verified this session, neither fatal but both wasting time if you hit them cold.**

**Run from `tools/cc`, never from the `claude-copilot` repo root.** A root-level run cannot even collect: `tools/cc/tests/conftest.py` and `tools/tc/tests/conftest.py` resolve to the same module path, and pytest aborts with `ImportPathMismatchError: ('tests.conftest', ...)` before running a single test. Pre-existing and structural (two sibling packages, each with a `tests/conftest.py`, no `__init__.py` and no rootdir mapping to disambiguate them), not something this work introduced, and out of scope here — but it means "I ran pytest and it exploded" is the expected outcome of the obvious command, so run it from the package directory.

**Do not add `-q` yourself.** `pyproject.toml`'s `addopts` already carries `-q`, so `pytest -q` becomes `-qq`, which suppresses the summary line entirely — you get a wall of dots, a correct exit code, and no totals. `D9` in this session removed a self-referential `--override-ini=addopts=` that hid the summary unconditionally; the residual `-q`-doubling footgun is milder but survives. A bare `pytest` reports normally; `pytest -o addopts=""` forces full reporting if you want it verbose. Worth cleaning up (drop `-q` from `addopts`, let callers choose) but deliberately not changed here, since touching shared test config while three agents were writing tests in the same tree was the wrong moment.

**Interpreter matters, and this is why the counts differ.** The 3 failures and 14 errors above appear only under the repo's own `.venv`. A bare system `python3 -m pytest` from `tools/cc` reports a clean `1100 passed, 14 skipped`, because neither the sibling `tc` package nor the `mcp` package is importable there, so both problem suites skip instead of failing. The venv number is the honest one — it is the environment where those tests actually execute. If you see `1100 passed, 14 skipped`, you are on system Python and the two broken suites were silently skipped, not fixed.

**A note on SourceKit.** If you're reading `native/*.swift` in an editor with SourceKit-based diagnostics, expect spurious red squiggles that do not reflect real compile errors — this is a known, pre-existing false-positive in this repo's SourceKit indexing, not something introduced this session. Judge correctness by the real compile (`scripts/build-user.command`/`scripts/build-admin.command`, or the build step inside `smoke-scenarios.sh`), never by the editor's live diagnostics.

**Do not, while verifying:** modify `~/.ssh/config`, `~/.claude/cc/config.json`, `~/.claude/memory/`, or anything under `~/Library/Application Support/CopilotControlTower/`; run `gh auth refresh`; run any `--apply` flag; or run `cc config set` against this real machine. The commands above are read-only-safe as written.

---

## 7. Where to pick up

In rough priority order — this is a sequencing/dependency list, not a time estimate:

1. **Completed — ratify and implement the least-privilege `cc auth grant` path (§3.1).** A dedicated organization OAuth App requests only `write:public_key`; the CLI owns its Keychain token and calls GitHub's key API directly.
2. **Completed — get a real visual pass on the seven Holding variants, adoption offer, completion fallback, and organization question.** See §4 for the deterministic native harness and production-hook exclusion.
3. **Completed — package a current signed/notarized User-app release candidate.** The corrected arm64 DMG from Control Tower source `e9ed732` embeds the notarized universal `cc` 1.7.1 helper from foundation `v5.13.1`. It passed the helper's live GitHub device-flow HTTPS release probe, Apple's notarization service, stapler, code-signing, Gatekeeper, mounted-DMG inspection, and a real-pixel device-code proof. The earlier `cc` 1.7.0 DMG is superseded because its frozen runtime omitted the CA trust bundle.
4. **Still open — publish signed foundation trust anchors** for the Claude and Codex foundation tags before treating their content as a verified supply-chain root. The release tooling exists, but the owner must approve a dedicated ENAC release-signing key; an existing GitHub authentication/push key is not accepted as the permanent trust root.
5. **Keep the closed `manifest_path` and encrypted-key regressions green (§4).** TASK-161 added prevention plus checksum detection for every active/legacy manifest path and Keychain-backed passphrase protection for newly generated keys.
6. **Decide the `cc config set --json` contract question (§3.2)** as part of, or ahead of, whatever WS-A contract work is already tracked for this repo.
7. **Migrate any product-owned passphrase-less key created by an older build (§4)** through an explicit rotation transaction. New keys are encrypted and Keychain-backed under TASK-161; existing live identities are not silently replaced.
8. **Keep the release branch pushed before packaging.** The native release
   pipeline refuses to advertise a branch or tag whose remote commit differs
   from local `HEAD`, and packages from a fresh checkout of that exact ref.
9. Resume the parent initiative at [`phase-6-ecosystem-install-and-onboarding-proof.md`](phase-6-ecosystem-install-and-onboarding-proof.md) §5 for the fresh-account and second-machine cold-start proof after item 4 is settled. The real-pixel portion is complete; the clean-machine transaction is not.
