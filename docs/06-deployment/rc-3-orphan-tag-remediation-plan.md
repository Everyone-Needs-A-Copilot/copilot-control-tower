# RC-3 remediation plan — existing orphan release tags

Owner-gated. Nothing in this document has been executed. It is the plan referenced by `rc.rc3.orphan_release_tags` and `stack.cs_ancestor`'s remediation text, written after the release-cut mechanism itself was fixed (see [`foundation-release-signing.md`](foundation-release-signing.md) and `scripts/foundation-snapshot-release.py`'s module docstring). No published tag was rewritten, moved, deleted, or force-pushed to produce this plan — that is explicitly out of scope for this session and requires the owner's own go-ahead.

## What's broken, confirmed live

`claude-copilot`: 83 tags total, 61 are orphan (parentless) snapshots — confirmed by iterating every tag with `git rev-list --count <tag>` and counting the ones that return `1`. The currently-pinned foundation ref, `v5.13.62` (`~/.config/copilot/copilot.layers.yml:145`), is one of them (`rev-list --count` = 1, `merge-base --is-ancestor v5.13.62 origin/main` exits 1).

`codex-copilot`: the currently-pinned foundation ref, `v0.6.2` (`copilot.layers.yml:196`), is the same shape (`rev-list --count` = 1, ancestry exits 1). `v0.6.1` has the identical shape per the phase-7 runbook's own live check.

`cli-copilot`: the currently-pinned foundation ref, `v0.3.5` (`copilot.layers.yml:96`), is also an orphan (`rev-list --count` = 1, ancestry exits 1) — this was wrongly assumed clean by an earlier pass and has now been corrected in `root_causes.py`'s `_RC3_KNOWN_BROKEN_PRODUCTS` and its real-machine test. `cli-copilot`'s release-cut path is not even `foundation-snapshot-release.py` (that tool's `PRODUCT_LAYOUTS` only knows `claude`/`codex`) — cli's orphan tag was produced by some other, unidentified process that independently reproduced the same anti-pattern. Finding and fixing that separate mechanism is a prerequisite this plan does not resolve.

## The corrective action

Tags are immutable once published (`foundation-release-signing.md`'s own standing rule, unchanged by this plan): **never move, delete, or force-push an existing tag.** The correction is always a **new** tag, cut correctly, with the manifest pin advanced to it — the old tag is left exactly as it is, permanently.

Per broken foundation, in order:

1. **Unblock the consumer coupling first (claude/codex only).** `cc.core.ecosystem.policy.verify_git_item` (`claude-copilot`) currently proves executable-item provenance by walking `git log -1 -- <path>` to find "the commit that last touched this file" and checking that commit's signature. A tag on a real branch commit (this plan's whole point) is TREESAME to its own history for every already-existing path, so that walk will resolve past the new tag to an ordinary, unsigned dev commit and fail-closed. This was verified empirically, not assumed (see the release-cut fix's own root-cause writeup). `claude-foundation` and `codex-foundation` both carry a non-empty `policy.allowed_signers` in `copilot.layers.yml`, so both are exposed; `cli-foundation`'s `policy.allowed_signers` is empty today, so cli is not currently gated by this specific consumer. **Do not re-cut and adopt a new claude/codex foundation tag until `verify_git_item` is updated to anchor trust on the signed tag + pinned commit instead of the `git log` walk** — otherwise every machine that pulls the new tag will start blocking foundation content materialization.
2. **Get a dedicated ENAC release SSH signing key approved**, per `foundation-release-signing.md`'s trust prerequisite — `FOUNDATION_ALLOWED_SIGNERS`/`--approved-fingerprint` are currently unset for a real release per that doc's own "Current status."
3. **Cut a new tag from the real branch tip** with the fixed tool (dry run first, review the JSON, then `--publish`):
   ```bash
   scripts/foundation-snapshot-release.py --repo /path/to/claude-copilot --source origin/main --branch main --tag v5.14.0 --product claude --signing-key <key>.pub --approved-fingerprint SHA256:<fp>
   # review the dry-run JSON (ancestry_verified: true, tag_signature: verified), then:
   scripts/foundation-snapshot-release.py --repo /path/to/claude-copilot --source origin/main --branch main --tag v5.14.0 --product claude --signing-key <key>.pub --approved-fingerprint SHA256:<fp> --publish
   ```
   Repeat for `codex-copilot` (`v0.6.3` or next). For `cli-copilot`, first locate/fix its actual release-cut mechanism (step 0 above still applies — it is not this tool).
4. **Independently re-verify the published tag** before advancing any pin (never trust the tool's own report alone):
   ```bash
   git -C /path/to/claude-copilot fetch --tags
   git -C /path/to/claude-copilot rev-list --count v5.14.0        # expect > 1
   git -C /path/to/claude-copilot merge-base --is-ancestor v5.14.0 origin/main   # expect exit 0
   claude-copilot/scripts/verify-foundation-release.sh /path/to/claude-copilot v5.14.0 <resolved-commit-sha> main
   ```
5. **Advance the pin**, one line each, in `~/.config/copilot/copilot.layers.yml` — `ref: v5.13.62` → `ref: v5.14.0` (line ~145), `ref: v0.6.2` → the new codex tag (line ~196), `ref: v0.3.5` → the new cli tag (line ~96) — once step 1's prerequisite is actually closed for that product.
6. **Re-run the conformance suite** to confirm the flip:
   ```bash
   cd claude-copilot/tools/cc && ./.venv/bin/python -m pytest "tests/conformance/test_layer2_stack.py::TestMachineTruth::test_cs_ancestor_fails_exactly_the_four_currently_broken_pins" "tests/conformance/test_rc_regressions.py::TestRealMachineRootCausesFailToday::test_rc3_claude_and_codex_foundation_tags_are_orphan_snapshots" -v
   ```
   Both tests assert today's broken set by name; once a foundation is fixed, its subject disappears from the failing set and the test itself needs updating in the same commit (`HARNESS-DESIGN.md`'s own "the update IS the acknowledgment" rule) — not before.

## Blast radius — what re-cutting breaks

- **`~/.config/copilot/copilot.layers.yml`**: the only machine-local consumer found; 3 of its 16 pins (`claude-foundation` line ~145, `codex-foundation` line ~196, `cli-foundation` line ~96) point at orphan tags and must be advanced per foundation, independently — advancing one does not require advancing the others.
- **`cc.core.ecosystem.policy.verify_git_item`** (`claude-copilot`): as above — the primary real risk. Un-updated, it fails closed (blocks materialization), it does not silently weaken trust — but it does break `cc update` for every machine that adopts a re-cut claude/codex tag until fixed.
- **`onboard.py`'s `parentless-snapshot-match` classification** (`claude-copilot`): built specifically to recognize a byte-identical checkout against a *parentless* pinned tag as `reuse`. A non-orphan tag no longer matches that special case; ordinary history-alignment classification applies instead, which is more permissive, not less, for any checkout that's a real fast-forward/clone of the tag — expected to be a strict improvement, but worth a dedicated test pass in that repo before relying on it.
- **`scripts/verify-foundation-release.sh`** (`claude-copilot`): already updated in this session to check ancestry instead of parentlessness — anyone with a local copy of the old version will get false rejections of a correctly re-cut tag; redistribute the fix.
- **Nothing else was found** referencing these specific tags by name outside of documentation/memory (`docs/40-initiatives/02-enac-self-onboarding/phases/phase-7-*.md`), which are historical run logs, not live consumers, and do not need updating.

## Explicitly not done in this session

No tag was rewritten, moved, deleted, or force-pushed. No new tag was cut or published. No signing key was requested or approved. No pin in `copilot.layers.yml` was changed. All of the above require the owner's explicit go-ahead per step, in the order listed (step 1 gates steps 3–5 for claude/codex specifically).
