# Foundation release signing

This is the operator procedure for publishing Claude and Codex foundation
trees that pass `cc`'s executable-content policy. It is a release how-to, not
an onboarding bypass.

## Trust prerequisite

Use a dedicated ENAC foundation release SSH signing key. Do not use a personal
GitHub authentication/push key as the compiled-in trust root.

Before a release:

1. Store the encrypted private key under the release custodian's control.
2. Register its public half with GitHub as an **SSH signing key** for the
   release identity.
3. Record its `SHA256:...` fingerprint through the approved ENAC trust
   channels.
4. Have the fingerprint explicitly approved before adding it to
   `FOUNDATION_ALLOWED_SIGNERS` in `cc`.

The public key and fingerprint are not secrets. The private key must never
enter a repository, build log, app bundle, or onboarding artifact.

## Why the release is a signed tag on the real branch commit, not an orphan snapshot

**Changed 2026-08-10 (RC-3 fix).** This tool used to create an orphan root
commit (`git commit-tree` with no parent) carrying the exact source tree, and
signed that instead of the branch tip. Every one of that design's real,
published tags (`claude-copilot`, `codex-copilot`, and — via a separate,
uncontrolled path that reproduced the same pattern — `cli-copilot`) fails
`git merge-base --is-ancestor <tag> origin/main`: a parentless commit is
definitionally not reachable by walking backward from any branch, no matter
how current its content is. That is RC-3.

The tool now signs `--source` (a real commit already on the branch) directly
with an annotated, signed **tag** — no commit is fabricated, so there is
nothing to be parentless. An unconditional ancestry guard
(`git merge-base --is-ancestor`) runs before every tag is created, dry run or
not, with no flag able to skip it, and refuses the cut if it fails.

**Known follow-on required before this is used for a real claude/codex
release:** `cc`'s executable-content policy
(`cc.core.ecosystem.policy.verify_git_item`, `claude-copilot` repo) currently
verifies "the commit that last changed each item" via `git log -1 -- <path>`.
That check relies on git's default pathspec history simplification, which
skips any commit whose diff for a path is empty relative to its parent — true
of the release tag's target commit for every executable path, always, now
that the tag points at the real branch commit rather than a freshly
reconstructed copy of it. Left unchanged, that policy check will silently
walk past the signed tag to whichever ordinary, unsigned dev commit last
touched the file, fail signature verification, and **block** materialization
of any foundation whose `policy.allowed_signers` is non-empty (today: claude
and codex). `verify_git_item` needs to anchor trust on the signed tag
(`ref`) and the pinned commit's tree directly instead of a `git log` walk
before any real claude/codex tag is re-cut with this tool — see
`scripts/verify-foundation-release.sh`'s RC-3 comment for the equivalent
change already made to the standalone verifier.

## Dry run

Dry run is the default. It operates in a temporary clone and changes neither
the source repository nor GitHub:

```bash
scripts/foundation-snapshot-release.py \
  --repo /absolute/path/to/claude-copilot \
  --source <reviewed-commit> \
  --branch main \
  --tag <new-claude-version> \
  --product claude \
  --signing-key /absolute/path/to/enac-foundation-release.pub \
  --approved-fingerprint SHA256:<approved-fingerprint>

scripts/foundation-snapshot-release.py \
  --repo /absolute/path/to/codex-copilot \
  --source <reviewed-commit> \
  --branch main \
  --tag <new-codex-version> \
  --product codex \
  --signing-key /absolute/path/to/enac-foundation-release.pub \
  --approved-fingerprint SHA256:<approved-fingerprint>
```

Each JSON result must report:

- the expected reviewed `source_commit`, matching `release_commit`;
- `ancestry_verified: true`;
- `tag_signature: "verified"`;
- the approved `signer_fingerprint`;
- a nonzero `executable_items_verified`; and
- `published: false`.

The tool refuses dirty source repositories, an existing tag, an invalid
version tag, a missing private-key half, a key that does not match the
explicit approved fingerprint, a `--source` that is not a provable ancestor
of `--branch` (RC-3), an unverified tag signature, or a path missing from the
target commit's tree.

## Publish

After a second person or explicit release-owner review of the dry-run output,
repeat the same command with `--publish`. This is the only mode that changes
GitHub. It pushes exactly the new annotated, signed tag pointing at the real,
already-ancestor commit it was cut from, then confirms the remote tag peels
to that commit.

Treat foundation release tags as immutable. If a release is wrong, publish a
new version and remove the bad version from the organization handoff; do not
move an existing tag.

## Compile and prove the anchors

For each approved signer fingerprint:

1. Add the exact fingerprint to the matching Claude/Codex tuple in
   `FOUNDATION_ALLOWED_SIGNERS`.
2. Run the `cc` policy and aggregate onboarding tests.
3. Clone the published tags into clean temporary mirrors.
4. Run materialization with the production policy and no permissive test
   override.
5. Confirm every executable operation is signed and none is blocked as
   unverified.
6. Build the distributed `cc` from that reviewed commit.

Do not add a fingerprint merely because a local signature verifies. GitHub
signing-key registration and release-owner approval are both part of the trust
decision.

## Current status

The signed-tag mechanism, its ancestry guard, and its dry-run verification
are implemented and proven against a disposable throwaway repository
(`scripts/tests/test_foundation_snapshot_release.sh`: a good cut passes
`rev-list --count` and `merge-base --is-ancestor`; a bad, non-ancestor cut is
refused before any tag is written). Public release tags and compiled signer
fingerprints remain blocked until a dedicated ENAC release key is selected,
registered, and approved, **and** until `verify_git_item` (see above) is
updated to stop depending on the orphan-snapshot shape for claude/codex.

61+ existing published tags across `claude-copilot`, `codex-copilot`, and
`cli-copilot` were cut by the prior orphan-snapshot mechanism and are not
fixed by this change — see the RC-3 remediation plan for what re-cutting them
requires and what it would break. No existing published tag was rewritten,
moved, or force-pushed by this change.
