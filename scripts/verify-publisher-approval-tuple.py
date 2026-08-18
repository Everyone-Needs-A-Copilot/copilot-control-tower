#!/usr/bin/python3
"""Validate an independently supplied first-install approval tuple.

This is a deterministic policy check, not an authority source. The caller must
obtain expected_manifest_sha256 through an independent channel and run this
from an independently trusted environment before root staging or Installer.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import stat
import sys


PACKAGE_ID = "com.everyoneneedsacopilot.controltower.publisher-bootstrap.pkg"
APP_ID = "com.everyoneneedsacopilot.controltower.publisher-bootstrap"
TEAM_ID = "3SYGVX2HB8"
CANONICAL_REMOTE = "https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
CDHASH = re.compile(r"^[0-9a-f]{40,64}$")
VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"error: {message}")


def exact_object(value: object, keys: set[str], label: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != keys:
        fail(f"{label} schema is not exact")
    return value


def exact_integer(value: object, expected: int, label: str) -> int:
    """Accept an exact JSON integer, never Python's bool-as-int subtype."""
    if type(value) is not int or value != expected:
        fail(f"{label} is unsupported")
    return value


def text(value: object, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        fail(f"{label} is invalid")
    return value


def version(value: object, label: str) -> tuple[int, int, int]:
    raw = text(value, VERSION, label)
    return tuple(int(part) for part in raw.split("."))  # type: ignore[return-value]


def regular_file(path: pathlib.Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except OSError:
        fail(f"{label} is unavailable")
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        fail(f"{label} must be a regular non-symlink file")


def main(arguments: list[str]) -> None:
    if len(arguments) != 4:
        fail("usage: verify-publisher-approval-tuple.py MANIFEST EXPECTED_MANIFEST_SHA256 PACKAGE")
    manifest_path = pathlib.Path(arguments[1])
    expected_manifest_sha256 = text(arguments[2], SHA256, "expected manifest SHA-256")
    package_path = pathlib.Path(arguments[3])
    if not manifest_path.is_absolute() or not package_path.is_absolute():
        fail("manifest and package paths must be absolute")
    regular_file(manifest_path, "approval manifest")
    regular_file(package_path, "signed package")

    manifest_bytes = manifest_path.read_bytes()
    if hashlib.sha256(manifest_bytes).hexdigest() != expected_manifest_sha256:
        fail("approval manifest differs from the independently expected digest")
    try:
        value = json.loads(manifest_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail("approval manifest is not valid JSON")

    root = exact_object(
        value,
        {"schema_version", "status", "source", "package", "application", "anti_rollback", "owner_approval"},
        "approval manifest",
    )
    exact_integer(root["schema_version"], 1, "approval manifest schema version")
    if root["status"] != "OWNER-APPROVED":
        fail("approval manifest is incomplete or has an unsupported schema")

    source = exact_object(root["source"], {"remote", "ref", "commit", "tree"}, "source")
    if source["remote"] != CANONICAL_REMOTE or not isinstance(source["ref"], str) or not source["ref"].startswith("refs/"):
        fail("source remote or immutable ref is invalid")
    text(source["commit"], GIT_SHA, "source commit")
    text(source["tree"], GIT_SHA, "source tree")

    package = exact_object(
        root["package"],
        {"identifier", "version", "installer_team_id", "final_signed_sha256"},
        "package",
    )
    if package["identifier"] != PACKAGE_ID or package["installer_team_id"] != TEAM_ID:
        fail("package identity is not approved")
    intended_version = version(package["version"], "package version")
    expected_package_sha256 = text(package["final_signed_sha256"], SHA256, "final signed package SHA-256")
    if hashlib.sha256(package_path.read_bytes()).hexdigest() != expected_package_sha256:
        fail("package differs from the owner-approved exact package")

    application = exact_object(
        root["application"],
        {"bundle_identifier", "team_id", "cdhash", "bundle_sha256"},
        "application",
    )
    if application["bundle_identifier"] != APP_ID or application["team_id"] != TEAM_ID:
        fail("application identity is not approved")
    text(application["cdhash"], CDHASH, "application CDHash")
    text(application["bundle_sha256"], SHA256, "application bundle SHA-256")

    rollback = exact_object(
        root["anti_rollback"],
        {"previous_package_version", "minimum_package_version"},
        "anti-rollback policy",
    )
    previous = version(rollback["previous_package_version"], "previous package version")
    floor = version(rollback["minimum_package_version"], "minimum package version")
    if intended_version <= previous or intended_version < floor:
        fail("package version does not advance the independently approved version floor")

    owner = exact_object(root["owner_approval"], {"approval_id", "approved_at_utc"}, "owner approval")
    if not isinstance(owner["approval_id"], str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{7,127}", owner["approval_id"]):
        fail("owner approval id is invalid")
    if not isinstance(owner["approved_at_utc"], str) or not re.fullmatch(
        r"20[0-9]{2}-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z", owner["approved_at_utc"]
    ):
        fail("owner approval timestamp is invalid")

    print(
        "owner-approved tuple matches exact package: "
        f"{source['commit']} {source['tree']} {package['version']} {expected_package_sha256}"
    )


if __name__ == "__main__":
    main(sys.argv)
