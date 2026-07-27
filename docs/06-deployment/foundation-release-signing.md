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

## Why the release is an orphan snapshot

`cc` verifies the commit that last changed each executable item. The existing
foundation histories include older unsigned last-touch commits, so adding a
signed tag to an ordinary descendant does not make every item verifiable.

The release tool creates an orphan root commit with the exact source tree and
signs both that commit and its annotated tag. Every path in that snapshot is
therefore introduced by the same verified release commit. Main-branch history
is not rewritten.

## Dry run

Dry run is the default. It operates in a temporary clone and changes neither
the source repository nor GitHub:

```bash
scripts/foundation-snapshot-release.py \
  --repo /absolute/path/to/claude-copilot \
  --source <reviewed-commit> \
  --tag <new-claude-version> \
  --product claude \
  --signing-key /absolute/path/to/enac-foundation-release.pub \
  --approved-fingerprint SHA256:<approved-fingerprint>

scripts/foundation-snapshot-release.py \
  --repo /absolute/path/to/codex-copilot \
  --source <reviewed-commit> \
  --tag <new-codex-version> \
  --product codex \
  --signing-key /absolute/path/to/enac-foundation-release.pub \
  --approved-fingerprint SHA256:<approved-fingerprint>
```

Each JSON result must report:

- the expected reviewed `source_commit`;
- `commit_signature: "verified"`;
- `tag_signature: "verified"`;
- the approved `signer_fingerprint`;
- a nonzero `executable_items_verified`; and
- `published: false`.

The tool refuses dirty source repositories, an existing tag, an invalid
version tag, a missing private-key half, a key that does not match the explicit
approved fingerprint, an unverified signature, or a path whose last-touch
commit is not the signed snapshot.

## Publish

After a second person or explicit release-owner review of the dry-run output,
repeat the same command with `--publish`. This is the only mode that changes
GitHub. It pushes exactly the new annotated tag and the orphan commit reachable
from it, then confirms the remote tag peels to the locally verified snapshot.

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

The snapshot mechanism and its dry-run verification are implemented. Public
release tags and compiled signer fingerprints remain blocked until a dedicated
ENAC release key is selected, registered, and approved.
