# Phase 6a — Honest setup: Holding, adoption, and organization sign-in (handoff)

> Initiative: [`02-enac-self-onboarding`](../README.md)
> Depends on: [`phase-6-ecosystem-install-and-onboarding-proof.md`](phase-6-ecosystem-install-and-onboarding-proof.md).
> Companion document: [`phase-6-honest-setup-work-record.md`](phase-6-honest-setup-work-record.md) — what was wrong, what changed, and why, organized by problem rather than by commit. Read that first for context; this document is the pickup: state, blockers, open decisions, known gaps, and how to verify and resume.
> **Taking this over cold?** Nothing here is merged or pushed. Read this document end-to-end before touching either repo, then run the verification commands in §6 yourself before trusting any number quoted below, including this document's own.

## 1. State

Both branches are unmerged and unpushed. Neither repo's working tree needed a code change to produce this handoff — the only new files are this document, its companion work record, and the three copied design specs (see the work record's "References" section for exact paths).

| Repo | Branch | Ahead of | Pushed? | Tip commit |
|---|---|---|---|---|
| `copilot-control-tower` | `app-build` | `origin/app-build` by 21 commits (5 of which are this sub-phase: `dca7e58`…`1aef610`) | Not pushed | `1aef610` |
| `claude-copilot` | `feat/adopt-and-project-setup` | local `main` by 6 commits (4 of which are this sub-phase: `e3e1826`…`20886b3`) | No remote branch exists at all (`git ls-remote --heads origin feat/adopt-and-project-setup` returns nothing) | `20886b3` |

**Both native app targets build clean.** Verified by running `scripts/tests/smoke-scenarios.sh`, which builds both bundles via `scripts/build-user.command --build-only` and `scripts/build-admin.command --build-only` before running any scenario; both build steps exited 0. Note for future builds: **you do not need to set `CC`/`PATH` yourself** — `scripts/build-user.command:68` and `scripts/build-admin.command:80` already hardcode `CC=/usr/bin/cc PATH=/usr/bin:$PATH` immediately before their own `swiftc` invocation, precisely because the `copilot` CLI installs itself as `cc` on this machine and shadows the real C compiler. That protection is already baked into the scripts; it only matters if you invoke `swiftc`/`swift build` directly, outside them.

**Test counts, verified by me, this session, from a clean invocation of each suite** (not re-derived from commit messages):

| Suite | Command | Result |
|---|---|---|
| App smoke scenarios | `bash scripts/tests/smoke-scenarios.sh` (from repo root) | **110 passed, 0 failed** — matches the commit-message figure exactly. |
| App admin bootstrap suite | `bash scripts/tests/test_admin_bootstrap.sh` | **206 passed, 0 failed** — matches the commit-message figure exactly. |
| CLI pytest suite | `cd claude-copilot/tools/cc && source .venv/bin/activate && pytest` | **1,097 passed, 3 failed, 14 errors, 0 skipped** (1,114 collected). |

**The CLI number does not match the commit messages' self-reported "1,100 passing, 14 skipped", and I'm flagging that rather than quietly reporting the commit figure.** I traced the discrepancy rather than assuming either number was wrong:

- The 3 failures are all in `tests/test_fts5_integration.py::TestCrossToolContract`, each failing with `ModuleNotFoundError: No module named 'tc'`. That test imports a sibling package, `tc.db.fts5_core` — this machine's separate Task Copilot CLI (`/opt/homebrew/bin/tc`), not something `cc`'s own `pyproject.toml` declares as a dependency anywhere. This `.venv` is scoped to `tools/cc` only, so `tc` was never on its `sys.path`.
- The 14 errors are all in `tests/test_mcp.py::TestMcpToolSchemas`, each failing with `AttributeError: 'Server' object has no attribute '_list_tools_handler'`. That test class has its own guard for exactly this situation — `tests/test_mcp.py:144`, `pytest.skip("mcp package not installed — schema tests skipped")` — but the guard only fires when `import mcp` itself fails. In this `.venv`, `mcp` **is** installed (an optional extra, `pip install -e ".[mcp]"` or `.[dev]"`-adjacent), so the guard doesn't fire, and the test proceeds to call a private attribute (`server._tool_handlers`/`_list_tools_handler`) that the installed `mcp` package version no longer exposes.
- Both `tests/test_mcp.py` and `tests/test_fts5_integration.py` last changed **2026-06-17** (`git log -1 -- <path>`), over a month before any of the four commits in this sub-phase, and neither file is touched by any of their diffs. **This is pre-existing environment coupling, not a regression from `e3e1826`/`8efe9ad`/`44fcfa5`/`20886b3`.** My best reconstruction: the environment the commit messages' own counts came from either didn't have the `mcp` extra installed (so those 14 tests skipped cleanly, matching "14 skipped") or ran in a combined workspace where a sibling `tc` install made the cross-tool test pass too — in either case, a different venv than the one at `claude-copilot/tools/cc/.venv` that exists on this machine right now.
- **Recommendation, not acted on** (out of scope for a read-only documentation pass): either (a) uninstall/avoid the `mcp` extra in this venv to reproduce the historical 14-skipped baseline exactly, and don't worry about the `tc` sibling gap since it was apparently already a known-environment-dependent 3 failures, or (b) fix both properly — guard `test_mcp.py`'s schema tests behind the actual API surface still present in whatever `mcp` version is pinned, and give `test_fts5_integration.py`'s cross-tool test the same `pytest.importorskip("tc", ...)`-style guard `test_mcp.py` already uses for `mcp`, so a `cc`-only venv doesn't fail a test that was never meant to run there.

**Config/secrets integrity, verified before and after every run in this session** (see §6 for the exact commands):

| Path | SHA-256 before | SHA-256 after | Changed? |
|---|---|---|---|
| `~/.claude/cc/config.json` | `604ad20169016fc258551579bc8fc787876eb143504ad901ddf8f54a210cd30d` | `604ad20169016fc258551579bc8fc787876eb143504ad901ddf8f54a210cd30d` | No |
| `~/.ssh/config` | `3afe60267212ab03742a784beeff4a402e3fa7b3016b4a5a84a0ac750b0d0385` | `3afe60267212ab03742a784beeff4a402e3fa7b3016b4a5a84a0ac750b0d0385` | No |
| `~/.claude/memory/` (tree hash) | `db5bdcf4003a6e1aeca09977e7817079cfdb589f830fe8a9a9147328143c201f` | `db5bdcf4003a6e1aeca09977e7817079cfdb589f830fe8a9a9147328143c201f` | No |
| `~/Library/Application Support/CopilotControlTower/standup-brief.{json,md}` | mtime `Jul 27 10:20:09`, before any test run this session | unchanged (not touched by the smoke or bootstrap suites, which use an isolated `$TMPDIR/ct-smoke-scenario-home.*` `HOME` override) | No |

I did not run `gh auth refresh`, any `--apply` flag, or `cc config set` against this machine, per the constraints for this task.

---

## 2. The owner action that blocks everything

Nothing in this sub-phase (or in Phase 6 generally) works for a real, first-time end user until the organization publishes a public repository, **`Everyone-Needs-A-Copilot/copilot-bootstrap`**, containing exactly one file, `bootstrap.yml`:

```yaml
org: Everyone-Needs-A-Copilot
github_app:
  client_id: "Ov23li2VmVUyOGXbwyDX"
```

Both values are non-secret by ratification: a GitHub organization name is public, and a GitHub OAuth/App **client id** is meant to be public (only the client *secret* is sensitive, and it is never collected anywhere in this flow). I confirmed both values are already correct and present in this machine's own local admin state — `~/Library/Application Support/CopilotControlTower/standup-brief.json`'s `org` and `github_app.client_id` fields match the two lines above exactly.

**I confirmed via `gh api` (read-only) that this repository does not exist yet:** `gh repo view Everyone-Needs-A-Copilot/copilot-bootstrap` returns "Could not resolve to a Repository." The four private `-internal` repositories (`knowledge-copilot-internal`, `cli-copilot-internal`, `claude-copilot-internal`, `codex-copilot-internal`) already exist, so a real standup run would be a no-op for those and would only add this one new public artifact plus a local pointer.

**Why this blocks everything:** without this public file, `cc auth login` cannot resolve which GitHub App to start a device-flow sign-in against on a Mac that has never signed in before (the deadlock problem 4 in the work record describes) — so no fresh Mac, including the two-machine cold-start proof Phase 6 itself is building toward, can complete first-run sign-in.

**Why it was not done as part of this session:** creating a public artifact under the organization's name is exactly the kind of action this project's own norms reserve for the owner (a real, externally-visible, one-way act on a live GitHub organization) — not a reversible local change a coding session should take unilaterally. The code to create and keep it in sync already exists and is unmodified by this session: `scripts/admin_bootstrap.sh`'s `_ensure_public_bootstrap_repo`, `_render_bootstrap_yml`, and `_ensure_bootstrap_yml` functions, called automatically as the last step of the existing standup sequence (`scripts/admin_bootstrap.sh:1719-1724`), guarded by the same leak-scan the rest of the script already uses (it refuses to write anything but `org` and `github_app.client_id`, and refuses to overwrite a `bootstrap.yml` carrying fields it didn't author).

**Exact steps for the owner:**

1. Confirm the standup brief is current at its fixed path (already true on this machine): `~/Library/Application Support/CopilotControlTower/standup-brief.md` / `.json`.
2. Dry run first, read-only: `bash scripts/admin_bootstrap.sh --verify --json` (no `--brief` needed; the fixed default path is used). Confirm a clean `pass` column and `must_fix: 0`.
3. Real run: `bash scripts/admin_bootstrap.sh`. This is additive/idempotent for everything that already exists (the four private repos, `ecosystem.yml`, branch protection) and will newly create `Everyone-Needs-A-Copilot/copilot-bootstrap` (public), write its `bootstrap.yml`, and write this Mac's own local org pointer.
4. Re-verify: `bash scripts/admin_bootstrap.sh --verify --json`. Confirm the new repository and file are reflected.
5. Spot-check from the outside, unauthenticated, that the whole point of the change actually holds: `curl -s https://raw.githubusercontent.com/Everyone-Needs-A-Copilot/copilot-bootstrap/main/bootstrap.yml` should return the two-line YAML above with no sign-in required.

---

## 3. Open decisions requiring a human

**3.1 — `cc auth grant` is unbuilt, and blocked on a genuine policy fork, not on effort.** H7 (the wizard variant that tells someone their GitHub sign-in is missing the `admin:public_key` permission needed to register this Mac's key) degrades to showing the documented command (`gh auth refresh -h github.com -s admin:public_key`) rather than a button, because the verb that would drive it doesn't exist. The fork: this organization's device flow authenticates through a **GitHub App**, but `admin:public_key` is a **classic OAuth scope** with no GitHub App equivalent — a GitHub App cannot request it at all. Options, none of them a coding decision:

- Register a dedicated classic OAuth App alongside the existing GitHub App, purely to carry this one scope. New admin-standup step; a second app identity to keep straight in support conversations.
- Borrow `gh`'s own public OAuth client id (the GitHub CLI's) to drive this one grant. Works today with no new registration, but embeds a third party's (GitHub's own CLI team's) application identity into this product's flow — a policy call about whose identity the product is willing to act through, not an engineering one.
- Something else not considered here.

Until this lands, every H7 screen (both the ordinary user path and the admin self-serve path) shows a command, never a button, and that is the honest, currently-correct behavior — not a bug to silently patch around.

**3.2 — `cc config set` has no `--json` output.** `docs/01-architecture/schemas/auth.schema.json` and `docs/03-design/control-tower-copy-deck.md` Appendix E.4 both flag this as open: the organization-question screen (§2.1.1) persists the org-name pointer via `cc config set github_app.org <name>`, and the CLI's own `commands/auth.py` docstring already names this as the app's job. But `cc config set` prints human-readable text and returns only an exit code — no structured payload the app can parse under invariant #1's versioned-contract discipline. The copy itself does not depend on the answer (no string claims the value was saved; the one failure path routes to an existing, honest H2 screen), but the **contract** question is real: is exit-code-only acceptable for a mutating verb under the versioned `--json` contract, or does persistence need a proper machine-readable verb of its own? This is a repo-architecture call (WS-A contract shape), not something to resolve by precedent-matching in isolation.

---

## 4. Known gaps, stated plainly

**No GUI test harness exists in this repo.** Every screen built or changed this session — all seven Holding variants, the widened adopt-offer, the completion-rule fallback, and the organization question — is verified only at the logic/string/CLI-seam layer, through `CT_SELFTEST`-driven scenario assertions against a mock CLI (`src-tauri/fixtures/mock-cc`). **The single visual confirmation across the entire session was one user screenshot of H6.** Nobody, including me, has watched any of these screens actually render on real pixels with real interaction. Treat every copy string and every layout claim in the work record and in the design specs as logically verified, not visually verified.

**`permissionNeededPending` and `reopenForConnectionOffer()`/`reopenForPermissionNeeded()` are implemented and wired, not merely designed.** `native/control-tower-tray.swift` derives both booleans live from the same read-only `ecosystemOnboardPlan` refresh the tray already performs (lines ~303–370), renders a Region 6 prompt/notice pair from them (~1109, ~1211), and each button calls into `WizardWindowController.shared.reopenForConnectionOffer()` / `.reopenForPermissionNeeded()` (`native/wizard.swift:5197`, `:5226`) to reopen the wizard directly onto the relevant screen. This closes the gap the `9d4730f` commit message itself flagged as "unwired." What remains genuinely open is the same GUI-test gap above: this mechanism is `CT_SELFTEST`-verified (scenarios S24–S26 in the smoke suite), never visually verified.

**The `copilotcontroltower://connect?organization=` deep link was designed, then deliberately dropped — not forgotten.** It would let the organization's download page hand the org name to the app directly, removing the one paste this whole sub-phase's fallback screen exists to handle. Reasoning recorded in `docs/03-design/control-tower-copy-deck.md` §2.1.1 and `docs/03-design/landing-site.md` §3.1: a custom URL scheme registers a handler any process on the machine can invoke, on the one code path that runs before any credential exists, and to stay safe it would still need a confirmation screen anyway — so it buys one saved paste at the cost of new, externally-triggerable attack surface. The copyable name on the download page carries nearly all the same benefit with none of the risk. Revisit once the organization-question flow has real usage and the saved paste is worth re-litigating the surface.

**One CLI sweep item flagged by this documentation pass, not by the commits themselves, and left unfixed:** `build_ecosystem_onboard_report`'s `manifest_path` parameter (`claude-copilot/tools/cc/src/cc/commands/onboard.py:1204`) defaults, when not explicitly passed, to the real `~/.config/copilot/copilot.layers.yml` (line ~1287). The `write_guard` prevention layer added in this sub-phase (`claude-copilot/tools/cc/src/cc/core/write_guard.py`) hard-refuses test-time writes to the real machine config, the real secrets file, and the real global memory root — but its `_FORBIDDEN_REAL_PATHS` denylist does **not** include this layer-manifest path. A future onboard test that forgets to pass `manifest_path=` (or forgets to monkeypatch `Path.home`) could silently write to the developer's real layer manifest, the same class of incident as the two recorded below, just not yet closed for this specific file. Nobody has hit this yet; it is a gap found by tracing the guard's own denylist against every real-path write the onboard module can reach, not a reported bug.

**The pre-existing passphrase-less bare key at the SSH happy path is still present, and still a real violation.** `ssh_identity.py`'s key-generation call (around line 485) runs `ssh-keygen -t ed25519 -f <key> -N "" -C <title>` — an empty passphrase, written to a bare file on disk. `docs/05-security/credentials-and-boundary.md` §6.1 requires the private key to "never leave the machine" via the OS keychain-backed `ssh-agent` (`ssh-add --apple-use-keychain` on macOS) and "never [go] to a bare plaintext file a git working tree or backup tool could pick up as content." The current happy path does exactly the thing §6.1 forbids. This was flagged, not fixed, in `e3e1826`'s own commit message ("the gate defends a property its own success path does not deliver") and remains true as of this writing — confirmed by reading the current code, not by trusting the old note.

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
# Expect: "admin_bootstrap tests: 206 passed, 0 failed"
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
# Expect (as of this session, verified): 1,097 passed, 3 failed, 14 errors,
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

**Do not, while verifying:** modify `~/.ssh/config`, `~/.claude/cc/config.json`, `~/.claude/memory/`, or anything under `~/Library/Application Support/CopilotControlTower/`; run `gh auth refresh`; run any `--apply` flag; or run `cc config set` against this real machine. All of the above are read-only-safe as written.

---

## 7. Where to pick up

In rough priority order — this is a sequencing/dependency list, not a time estimate:

1. **Owner action (§2): publish `Everyone-Needs-A-Copilot/copilot-bootstrap`.** Nothing downstream of this (a real fresh-Mac sign-in, the Phase 6 two-machine cold-start proof) can be genuinely tested until this exists. Low complexity, no code dependency — it is purely a "run the existing script for real" action gated on the owner's willingness to make a public GitHub artifact.
2. **Resolve the `cc auth grant` fork (§3.1).** This is a decision, not a build task; once made, building the verb and wiring H7's button is a contained, previously-scoped change (the shape is already fully specified in `docs/03-design/control-tower-copy-deck.md` §2.9.3 and the copied `adopt-and-honesty-copy-spec.md` §3.5–§3.7).
3. **Get a real visual pass on at least the seven Holding variants, the adopt offer, and the organization question**, on real pixels, before trusting any of this against an actual non-technical user. This is the single largest gap between "logically verified" and "known to work" in the whole sub-phase (§4).
4. **Close the `manifest_path` write_guard gap (§4)** by adding `~/.config/copilot/copilot.layers.yml` (and its two legacy fallback paths) to `write_guard.py`'s `_FORBIDDEN_REAL_PATHS`, before it produces a third incident of the same shape as §5's two.
5. **Decide the `cc config set --json` contract question (§3.2)** as part of, or ahead of, whatever WS-A contract work is already tracked for this repo.
6. **Fix the passphrase-less bare key (§4)** to route the on-device SSH private key through the keychain-backed `ssh-agent` per `credentials-and-boundary.md` §6.1, closing the last flagged-but-unfixed security gap from this sequence.
7. **Push both branches** once the owner is satisfied with the state above — `app-build` is 21 commits ahead of `origin/app-build`; `feat/adopt-and-project-setup` has no remote branch at all yet.
8. Resume the parent initiative at [`phase-6-ecosystem-install-and-onboarding-proof.md`](phase-6-ecosystem-install-and-onboarding-proof.md) §5 (the second-machine cold-start proof) once 1–4 above are settled; that document's own execution plan (§8) and acceptance criteria are unchanged by this sub-phase and remain the next real milestone.
