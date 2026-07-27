#!/usr/bin/env python3
"""Create and verify a signed, orphan foundation release snapshot.

The default is a dry run in a temporary clone. ``--publish`` is the only
operation that changes a remote: it pushes exactly one new signed tag and the
orphan commit reachable from it. The source repository and working tree are
never modified.
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
        ("commit.gpgsign", "true"),
    ):
        git(checkout, "config", key, value)


def create_snapshot(
    checkout: Path,
    *,
    source_commit: str,
    tag: str,
) -> str:
    tree = git(checkout, "rev-parse", f"{source_commit}^{{tree}}").stdout.strip()
    snapshot = git(
        checkout,
        "commit-tree",
        "-S",
        "-m",
        f"foundation snapshot {tag}",
        tree,
    ).stdout.strip()
    git(
        checkout,
        "tag",
        "-s",
        "-m",
        f"Foundation release {tag}",
        tag,
        snapshot,
    )
    git(checkout, "verify-commit", snapshot)
    git(checkout, "verify-tag", tag)
    return snapshot


def verify_item_provenance(
    checkout: Path,
    *,
    snapshot: str,
    items: list[str],
) -> None:
    for item in items:
        last_commit = git(
            checkout,
            "log",
            "-1",
            "--format=%H",
            snapshot,
            "--",
            item,
        ).stdout.strip()
        if last_commit != snapshot:
            raise ReleaseError(
                f"{item} resolves to {last_commit or 'no commit'}, not the signed snapshot"
            )


def publish_tag(
    checkout: Path,
    *,
    remote: str,
    tag: str,
    snapshot: str,
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
    if not peeled or peeled[0] != snapshot:
        raise ReleaseError("remote tag did not peel to the verified snapshot commit")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a signed orphan snapshot so every executable item is "
            "last-touched by one verified foundation release commit."
        )
    )
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--source", default="HEAD")
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
            snapshot = create_snapshot(
                checkout,
                source_commit=source_commit,
                tag=args.tag,
            )
            verify_item_provenance(
                checkout,
                snapshot=snapshot,
                items=items,
            )
            if args.publish:
                publish_tag(
                    checkout,
                    remote=remote,
                    tag=args.tag,
                    snapshot=snapshot,
                )

        result = {
            "schema_version": "1.0",
            "product": args.product,
            "tag": args.tag,
            "source_commit": source_commit,
            "snapshot_commit": snapshot,
            "signer_fingerprint": fingerprint,
            "executable_items_verified": len(items),
            "commit_signature": "verified",
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
                    "schema_version": "1.0",
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
