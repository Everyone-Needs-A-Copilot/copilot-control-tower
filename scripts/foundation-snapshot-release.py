#!/usr/bin/env python3
"""Create and verify a signed foundation release tag.

RC-3 root cause (fixed here): every prior release cut by this tool created a
brand-new PARENTLESS commit via ``git commit-tree`` (no ``-p``) and tagged
that instead of the branch tip. A commit with no parent can never satisfy
``git merge-base --is-ancestor <tag> <branch>`` -- it is not reachable by
walking backward from the branch at all, regardless of how "current" its
content is. That produced 61+ real, published tags (`claude-copilot`,
`codex-copilot`, `cli-copilot`'s release-cut path all shared this defect)
whose pin-ancestry can never be proven, only their raw git-object validity.

The fix: sign the release AT the real branch commit (``--source``, e.g.
``HEAD`` while checked out on ``main``) with an annotated, signed tag. No new
commit is fabricated, so there is nothing to be parentless -- the tag target
is, by construction, whatever real commit ``--source`` already resolved to on
the branch. An unconditional ancestry guard (``verify_ancestry``, RC-3) still
re-proves this with ``git merge-base --is-ancestor`` before every tag is
created, dry run or not, with no flag or environment variable able to skip
it -- this ecosystem's CI gate is opt-in and has skipped every tagged release
to date, so this tool refuses to depend on that gate firing.

The default is a dry run in a temporary clone. ``--publish`` is the only
operation that changes a remote: it pushes exactly one new signed tag
pointing at the real, already-ancestor commit it was cut from. The source
repository and working tree are never modified.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
PRODUCT_LAYOUTS = {
    "claude": (
        ".claude",
        ("agents", "skills", "commands", "protocol", "cli-integrations"),
    ),
    "codex": (".", ("plugins",)),
    # RC-3 remediation (2026-08-11): added so `cli-copilot`'s foundation
    # release can be re-cut through this same fixed, ancestry-guarded path
    # instead of whatever separate, unidentified process previously produced
    # its own orphan tag (see rc-3-orphan-tag-remediation-plan.md). Mirrors
    # `codex`'s shape: one top-level product directory holding the real
    # shipped package, not a `.claude`-style multi-dimension split.
    "cli": (".", ("copilot_cli",)),
    # Knowledge foundations can carry executable framework surfaces beside
    # ordinary prose. Verify every top-level item beneath those executable
    # surfaces while leaving non-executable knowledge content integrity-pinned
    # by the normal layer lock.
    "knowledge": (".", (".claude", "plugins", "scripts")),
}


class ReleaseError(RuntimeError):
    pass


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "command failed"
        raise ReleaseError(f"{args[0]} failed: {detail}")
    return result


def git(
    repo: Path,
    *args: str,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return run(["git", "-C", str(repo), *args], check=check)


def signing_key_fingerprint(public_key: Path) -> str:
    result = run(["ssh-keygen", "-lf", str(public_key), "-E", "sha256"])
    fields = result.stdout.split()
    if len(fields) < 2 or not fields[1].startswith("SHA256:"):
        raise ReleaseError("ssh-keygen did not return a SHA256 fingerprint")
    return fields[1]


def validate_inputs(args: argparse.Namespace) -> tuple[Path, Path, str, str]:
    source_repo = args.repo.expanduser().resolve()
    public_key = args.signing_key.expanduser().resolve()
    if not (source_repo / ".git").exists():
        raise ReleaseError(f"not a Git working tree: {source_repo}")
    if not TAG_RE.fullmatch(args.tag):
        raise ReleaseError("tag must be an exact semantic version such as v5.13.0")
    if not public_key.is_file() or public_key.suffix != ".pub":
        raise ReleaseError("--signing-key must name an SSH public-key file")
    private_key = Path(str(public_key)[: -len(".pub")])
    if not private_key.is_file():
        raise ReleaseError(
            f"the private half of the signing key is not available at {private_key}"
        )
    fingerprint = signing_key_fingerprint(public_key)
    if fingerprint != args.approved_fingerprint:
        raise ReleaseError(
            "signing-key fingerprint does not match --approved-fingerprint: "
            f"expected {args.approved_fingerprint}, got {fingerprint}"
        )

    status = git(source_repo, "status", "--porcelain").stdout.strip()
    if status:
        raise ReleaseError(
            "source repository is dirty; commit or preserve changes first"
        )
    source_commit = git(
        source_repo,
        "rev-parse",
        "--verify",
        f"{args.source}^{{commit}}",
    ).stdout.strip()
    if (
        git(
            source_repo, "show-ref", "--verify", f"refs/tags/{args.tag}", check=False
        ).returncode
        == 0
    ):
        raise ReleaseError(f"tag already exists locally: {args.tag}")
    return source_repo, public_key, source_commit, fingerprint


def executable_items(checkout: Path, product: str) -> list[str]:
    root_name, dimensions = PRODUCT_LAYOUTS[product]
    root = checkout if root_name == "." else checkout / root_name
    items: list[str] = []
    for dimension in dimensions:
        dimension_root = root / dimension
        if not dimension_root.is_dir():
            continue
        for child in sorted(dimension_root.iterdir()):
            if child.name.startswith("."):
                continue
            items.append(child.relative_to(checkout).as_posix())
    if not items:
        raise ReleaseError(f"no executable foundation items found for {product}")
    return items


def configure_verification(
    checkout: Path,
    *,
    public_key: Path,
    allowed_signers: Path,
    source_repo: Path,
) -> None:
    key_text = public_key.read_text(encoding="utf-8").strip()
    if not key_text.startswith(("ssh-ed25519 ", "ssh-rsa ", "ecdsa-sha2-")):
        raise ReleaseError("unsupported SSH public-key format")
    allowed_signers.write_text(
        f'enac-foundation namespaces="git" {key_text}\n',
        encoding="utf-8",
    )

    name = git(source_repo, "config", "--get", "user.name", check=False).stdout.strip()
    email = git(
        source_repo, "config", "--get", "user.email", check=False
    ).stdout.strip()
    if not name or not email:
        raise ReleaseError("source repository must configure user.name and user.email")

    for key, value in (
        ("user.name", name),
        ("user.email", email),
        ("gpg.format", "ssh"),
        ("user.signingkey", str(public_key)),
        ("gpg.ssh.allowedSignersFile", str(allowed_signers)),
    ):
        git(checkout, "config", key, value)


def verify_ancestry(
    source_repo: Path,
    *,
    commit: str,
    branch: str,
) -> str:
    """Unconditional RC-3 guard: refuse to cut a release whose target commit
    is not a real, provable ancestor of ``branch``. Runs on EVERY invocation
    -- dry run or ``--publish`` -- with no flag or env var able to skip it,
    BEFORE anything is cloned, checked out, or signed. This ecosystem's
    other release gate (Control Tower's CI check) is ``if:
    vars.RELEASE_CI_ENABLED == 'true'`` and has skipped every tagged release
    to date, so the only gate this tool trusts to actually fire is one baked
    directly into its own control flow.

    Runs against ``source_repo`` directly, never a freshly cloned copy: a
    `git clone` only transfers objects reachable from a ref, so a bad cut
    (a `commit-tree` result with no parent and no ref pointing at it, e.g.
    the exact shape `--source` would be pointed at by mistake) would simply
    be ABSENT from a fresh clone rather than failing this check cleanly --
    `rev-parse`/`merge-base` resolve any object already in the local object
    database by SHA regardless of ref reachability, so this must run before
    any clone is attempted.

    Prefers ``origin/<branch>`` (what the remote actually has) and falls
    back to a local ``<branch>`` (mirrors `stack.py`'s own
    `_CANDIDATE_DEFAULT_BRANCH_REFS` convention) -- returns whichever
    resolved, for evidence/logging.
    """
    for candidate in (f"origin/{branch}", branch):
        resolved = git(
            source_repo, "rev-parse", "--verify", f"{candidate}^{{commit}}", check=False
        )
        if resolved.returncode == 0:
            branch_ref = candidate
            break
    else:
        raise ReleaseError(
            f"cannot verify ancestry: neither 'origin/{branch}' nor {branch!r} "
            f"resolves in {source_repo} -- pass --branch with a real branch name "
            "(default: main)"
        )
    ancestry = git(
        source_repo, "merge-base", "--is-ancestor", commit, branch_ref, check=False
    )
    if ancestry.returncode != 0:
        raise ReleaseError(
            f"refusing to cut a release: {commit} is not an ancestor of "
            f"{branch_ref} (git merge-base --is-ancestor {commit} "
            f"{branch_ref} exited {ancestry.returncode}). This is RC-3's "
            "exact defect -- a release-cut step that is not a real descendant "
            "of the branch it claims -- refused before any tag was written."
        )
    return branch_ref


def create_release_tag(
    checkout: Path,
    *,
    source_commit: str,
    tag: str,
) -> str:
    """Sign ``source_commit`` -- a real commit already on the branch,
    verified by ``verify_ancestry`` before this ever runs -- with an
    annotated, signed tag. No new commit is created: the release tag's
    target IS the branch commit it was cut from, so ``git rev-list --count
    <tag>`` reflects the branch's real history and ``git merge-base
    --is-ancestor <tag> <branch>`` succeeds by construction, not by
    coincidence. (The prior implementation fabricated a brand-new parentless
    commit with ``git commit-tree`` here -- that is RC-3's root cause; see
    the module docstring.)
    """
    git(
        checkout,
        "tag",
        "-s",
        "-m",
        f"Foundation release {tag}",
        tag,
        source_commit,
    )
    git(checkout, "verify-tag", tag)
    return source_commit


def verify_item_provenance(
    checkout: Path,
    *,
    release_commit: str,
    items: list[str],
) -> None:
    """Confirm every declared executable item genuinely exists in the tree
    the release tag points at.

    Deliberately NOT a ``git log -1 -- item`` walk (the prior
    implementation's technique): that relies on git's default pathspec
    history simplification, which silently skips any commit whose diff for
    a path is empty relative to its parent -- true of every path here,
    always, since the release commit IS the source commit, not a
    reconstructed copy of it. Walking history for "who last touched this"
    is the right question for an ordinary, unsigned dev commit; it is the
    wrong question for a release tag, where the only fact that matters is
    "does the exact commit this signed tag points at contain this item" --
    answered directly via the tree, with no dependency on git log's commit
    simplification rules.
    """
    for item in items:
        exists = git(
            checkout, "cat-file", "-e", f"{release_commit}:{item}", check=False
        )
        if exists.returncode != 0:
            raise ReleaseError(
                f"{item} does not exist in {release_commit}'s tree -- the tag "
                "target is missing declared executable content"
            )


def publish_tag(
    checkout: Path,
    *,
    remote: str,
    tag: str,
    release_commit: str,
) -> None:
    existing = run(
        ["git", "ls-remote", "--tags", remote, f"refs/tags/{tag}"],
        check=False,
    )
    if existing.returncode != 0:
        raise ReleaseError(existing.stderr.strip() or "could not inspect remote tags")
    if existing.stdout.strip():
        raise ReleaseError(f"tag already exists remotely: {tag}")

    git(checkout, "push", remote, f"refs/tags/{tag}:refs/tags/{tag}")
    peeled = run(
        ["git", "ls-remote", "--tags", remote, f"refs/tags/{tag}^{{}}"],
    ).stdout.split()
    if not peeled or peeled[0] != release_commit:
        raise ReleaseError("remote tag did not peel to the verified release commit")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sign an existing branch commit as a foundation release tag -- "
            "never a reconstructed, parentless commit -- and refuse to cut "
            "it at all unless it is a provable ancestor of the branch "
            "(RC-3)."
        )
    )
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--source", default="HEAD")
    parser.add_argument(
        "--branch",
        default="main",
        help=(
            "The branch this release must be a real, provable ancestor of "
            "(RC-3 guard; checked as origin/<branch> in a fresh clone). "
            "Default: main."
        ),
    )
    parser.add_argument("--tag", required=True)
    parser.add_argument("--product", choices=sorted(PRODUCT_LAYOUTS), required=True)
    parser.add_argument(
        "--signing-key",
        type=Path,
        required=True,
        help="Dedicated ENAC release SSH public key; private half must be adjacent.",
    )
    parser.add_argument(
        "--approved-fingerprint",
        required=True,
        help="Exact approved SHA256 fingerprint for the dedicated release key.",
    )
    parser.add_argument(
        "--publish",
        action="store_true",
        help="Push the verified new tag to the source repository's origin.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source_repo, public_key, source_commit, fingerprint = validate_inputs(args)
        remote = git(source_repo, "remote", "get-url", "origin").stdout.strip()
        if not remote:
            raise ReleaseError("source repository has no origin remote")

        # RC-3 guard: unconditional, runs before anything is cloned, checked
        # out, or signed -- on every invocation, dry run or not. Nothing in
        # this tool can bypass it.
        resolved_branch = verify_ancestry(
            source_repo, commit=source_commit, branch=args.branch
        )

        with tempfile.TemporaryDirectory(prefix="foundation-snapshot-") as raw_temp:
            temp_root = Path(raw_temp)
            checkout = temp_root / "checkout"
            run(
                [
                    "git",
                    "clone",
                    "--quiet",
                    "--no-local",
                    str(source_repo),
                    str(checkout),
                ]
            )
            git(checkout, "checkout", "--quiet", "--detach", source_commit)
            allowed_signers = temp_root / "allowed_signers"
            configure_verification(
                checkout,
                public_key=public_key,
                allowed_signers=allowed_signers,
                source_repo=source_repo,
            )
            items = executable_items(checkout, args.product)
            release_commit = create_release_tag(
                checkout,
                source_commit=source_commit,
                tag=args.tag,
            )
            verify_item_provenance(
                checkout,
                release_commit=release_commit,
                items=items,
            )
            if args.publish:
                publish_tag(
                    checkout,
                    remote=remote,
                    tag=args.tag,
                    release_commit=release_commit,
                )

        result = {
            "schema_version": "1.1",
            "product": args.product,
            "tag": args.tag,
            "branch": args.branch,
            "ancestry_branch_ref": resolved_branch,
            "source_commit": source_commit,
            "release_commit": release_commit,
            "signer_fingerprint": fingerprint,
            "executable_items_verified": len(items),
            "ancestry_verified": True,
            "tag_signature": "verified",
            "published": bool(args.publish),
            "remote": remote,
        }
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, ReleaseError, UnicodeError) as exc:
        print(
            json.dumps(
                {
                    "schema_version": "1.1",
                    "error": {
                        "code": "foundation-release-refused",
                        "message": str(exc),
                    },
                },
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
