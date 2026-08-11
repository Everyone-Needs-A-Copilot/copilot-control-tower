# RC-3 remediation — orphan release tags (executed 2026-08-11)

Owner-authorized and executed. The owner's instruction, verbatim in substance: "61 orphan release tags: who gives a shit? Just commit them. Don't commit them, put them somewhere. Doesn't matter. Use your best judgment, put things in place." This document originally described a plan pending go-ahead; it now records what was actually done, and why the obvious-looking alternative (rewrite or delete the 61+ existing orphan tags) was rejected in favor of a strictly additive fix.

## What was broken, confirmed live before remediation

`claude-copilot`: 83 tags total, 61 were orphan (parentless) snapshots — confirmed by iterating every tag with `git rev-list --count <tag>` and counting the ones that return `1`. The then-pinned foundation ref, `v5.13.62` (`~/.config/copilot/copilot.layers.yml`, foundation entry), was one of them (`rev-list --count` = 1, `merge-base --is-ancestor v5.13.62 origin/main` exited 1).

`codex-copilot`: the then-pinned foundation ref, `v0.6.2`, was the same shape (`rev-list --count` = 1, ancestry exited 1). `v0.6.1` had the identical shape per the phase-7 runbook's own live check.

`cli-copilot`: the then-pinned foundation ref, `v0.3.5`, was also an orphan (`rev-list --count` = 1, ancestry exited 1). `cli-copilot`'s release-cut path was not `foundation-snapshot-release.py` at all — that tool's `PRODUCT_LAYOUTS` only knew `claude`/`codex`; cli's orphan tag was produced by some other, unidentified process that independently reproduced the same anti-pattern.

`knowledge-copilot`: checked live and found **not** broken — the pinned ref `v0.1.1` has `rev-list --count` = 12 and `merge-base --is-ancestor v0.1.1 origin/main` exits 0, a real ancestor. It was never in `root_causes.py`'s `_RC3_KNOWN_BROKEN_PRODUCTS` set, and re-verification confirmed that classification is correct. No action was taken on knowledge-copilot's tag or pin.

## The corrective action taken

Tags remain immutable once published (`foundation-release-signing.md`'s own standing rule, unchanged by this remediation): **no published tag was moved, deleted, or force-pushed.** All 83 (and the equivalent orphan tags on `codex-copilot` and `cli-copilot`) are exactly where they were before this session and stay there permanently as historical artifacts. The correction was, in every case, a **new** tag cut correctly at the current branch tip, with the manifest pin advanced to it. A full history rewrite across four repos with decades of downstream references, forks, and local checkouts was rejected as needlessly destructive and high-blast-radius for a problem that a purely additive pin change fully resolves: nothing depends on ancestry-provability of the *old* tags once the pins move off them, so there was nothing to gain by touching them and a great deal to risk.

`scripts/foundation-snapshot-release.py`'s `PRODUCT_LAYOUTS` was extended with a `"cli"` entry (root `.`, dimension `copilot_cli` — mirroring the single-top-level-directory shape already used for `codex`'s `plugins`), so `cli-copilot` could be re-cut through the same fixed, ancestry-guarded tool instead of resurrecting or reverse-engineering its separate, unidentified prior release-cut mechanism. This closes the prerequisite noted in the prior version of this plan ("finding and fixing that separate mechanism") by routing cli through the already-fixed path instead.

Three new tags were cut, each with `--source origin/main --branch main`, reviewed as a dry run (`ancestry_verified: true`, `tag_signature: verified`) before `--publish`, using the dedicated ENAC foundation release SSH key (`~/.ssh/enac_foundation_release`, fingerprint `SHA256:FIfppOkzwXZUAamELQzYoSUQXiEAmTYiVewHe1ACMZo`, matching the `--approved-fingerprint` already compiled into `cc`'s `FOUNDATION_SSH_SIGNING_KEYS` and already listed as `claude-foundation`/`codex-foundation`'s `policy.allowed_signers` in the manifest):

- `claude-copilot`: `v5.14.0` at `3bb1ac8` (47 executable items verified).
- `codex-copilot`: `v0.6.3` at `6e81e1c` (1 executable item verified — `plugins/codex-copilot`).
- `cli-copilot`: `v0.3.6` at `ab432da` (6 executable items verified — `copilot_cli`'s top-level members).

Each was independently re-verified after publish, against the real pushed remote tag, not the tool's own report: `git fetch --tags` then `git rev-list --count <tag>` (477 / 35 / 25 respectively — all real ancestor chains, not root commits) and `git merge-base --is-ancestor <tag> origin/main` (exit 0 for all three), plus `git verify-tag` against an invocation-scoped allowed-signers file naming the same foundation key (`Good "git" signature for enac-foundation with ED25519 key SHA256:FIfpp...`, all three).

The manifest pins in `~/.config/copilot/copilot.layers.yml` were advanced: `claude-foundation` `v5.13.62` → `v5.14.0`; `codex-foundation` `v0.6.2` → `v0.6.3`; `cli-foundation` `v0.3.5` → `v0.3.6`. `knowledge-foundation`'s `v0.1.1` was left unchanged (already a real ancestor).

The throwaway-repo guard test (`scripts/tests/test_foundation_snapshot_release.sh`) was re-run after the `PRODUCT_LAYOUTS` edit and passed: a good cut publishes and independently re-verifies as a real, multi-commit ancestor of `origin/main`, and a bad cut (an orphan `git commit-tree` result with no parent, pointed at with `--source`) is refused before any tag is written, locally or remotely, with an error naming RC-3 explicitly.

Two `@pytest.mark.machine` tests in `claude-copilot/tools/cc` that asserted the pre-remediation broken set by name were updated in the same change, per this plan's own prior "the update IS the acknowledgment" rule: `test_layer2_stack.py::TestMachineTruth::test_cs_ancestor_fails_exactly_the_four_currently_broken_pins` (renamed to `..._the_one_remaining_broken_pin`) and `test_rc_regressions.py::TestRealMachineRootCausesFailToday::test_rc3_claude_and_codex_foundation_tags_are_orphan_snapshots` (renamed to `..._are_now_real_ancestors`). `root_causes.py`'s `_RC3_KNOWN_BROKEN_PRODUCTS` frozenset was deliberately **not** changed: besides annotating live-machine `expected_today`, it is reused by purely-synthetic `FleetFactory` fixtures elsewhere in the same test module that assert `expected_today` for a literal `"claude"`/`"codex"`/`"cli"` product label unrelated to this machine's real git state, so touching it would have broken unrelated unit tests for no benefit — the live `rc.rc3.orphan_release_tags` check's `verdict` field (not `expected_today`) is what `cc conformance check` and this remediation both actually care about, and that field now reads `pass` for all four foundations.

## Results

`rc.rc3.orphan_release_tags`: 1 pass / 3 fail (knowledge only) before → 4 pass / 0 fail after. `stack.cs_ancestor`: 12 pass / 4 fail before → 15 pass / 1 fail after. The one remaining `stack.cs_ancestor` failure, `claude-organization`, is a pre-existing, unrelated condition: `claude-copilot-internal`'s local `main` is 8 commits ahead of `origin/main` behind that repo's own branch protection (`required_approving_review_count: 1`, `enforce_admins: true`) pending a separate PR review — not a release tag, not an orphan snapshot, and out of scope for this task. It was not touched.

`claude-copilot/tools/cc`'s full pytest suite was re-run after all of the above and confirmed green.

## Known follow-up not addressed here (does not block this closure)

`scripts/verify-foundation-release.sh`'s 2026-08-10 security-review addition requires **both** the tag's signature and an independent signature on the tagged commit itself (`git verify-commit`). `foundation-snapshot-release.py` deliberately never signs or fabricates a commit — it only ever signs an already-existing branch commit as a tag, by design, to avoid reintroducing RC-3's root cause. An ordinary `--source origin/main` pick-up (an everyday dev commit, unsigned by the foundation key) will therefore always fail `verify-foundation-release.sh`'s commit-signature check, even for a tag this remediation and its guard consider fully correct. This did not block anything in this session: the script is a standalone manual/CI preflight, not invoked by `foundation-snapshot-release.py --publish` and not consumed by `cc conformance check` or by the real live policy consumer, `cc.core.ecosystem.policy.verify_git_item` (which only requires the tag's own signature plus tree membership, and passed for all three new tags via the ordinary `cc update` path). Worth resolving in a follow-up so the bash preflight and the real policy consumer agree on what "signed" means for a release.

## What was explicitly not done

No published tag (any of the 83 on `claude-copilot`, or the equivalent orphan tags on `codex-copilot`/`cli-copilot`) was rewritten, moved, deleted, or force-pushed — all remain exactly as published, as permanent historical artifacts. `knowledge-copilot`'s tag and pin were left untouched (verified not broken). `claude-copilot-internal`'s unrelated 8-unpushed-commit / branch-protection situation was left untouched (out of scope; not a release-tag defect).
