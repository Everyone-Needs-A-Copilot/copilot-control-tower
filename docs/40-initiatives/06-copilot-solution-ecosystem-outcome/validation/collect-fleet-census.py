#!/usr/bin/env python3
"""Create a content-free, read-only, exact-path fleet census.

The collector reads only explicit classification rows, Git metadata, the
project component lock, and the machine-local entitlement ledger. It never
invokes an installer, fetches a remote, reads project file content except for
framework-owned checksum verification, or writes inside a candidate repo.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import stat
import subprocess
import tomllib
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

WILDCARD_CHARACTERS = frozenset("*?[]{}")
SUPPORTED_CLASSES = frozenset({"PRODUCT", "SITE-CONTENT"})
COMPONENT_FAMILIES = ("claude", "codex", "cli", "knowledge")
PROTECTED_ROLES = ("organization", "department")


def exact_path(value: str | Path) -> Path:
    candidate = Path(os.path.abspath(Path(value).expanduser()))
    if not candidate.is_absolute() or any(char in str(candidate) for char in WILDCARD_CHARACTERS):
        raise ValueError(f"path must be absolute and wildcard-free: {candidate}")
    return candidate


def git_state(repo: Path) -> tuple[str, int, list[str]]:
    if repo.is_symlink() or not repo.is_dir():
        return "unavailable", 0, ["repo-missing-or-symlinked"]
    root = subprocess.run(
        ("git", "-C", str(repo), "rev-parse", "--show-toplevel"),
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    if root.returncode != 0:
        return "unavailable", 0, ["not-a-git-repository"]
    try:
        actual = exact_path(root.stdout.strip())
    except ValueError:
        return "unavailable", 0, ["invalid-git-root"]
    if actual != repo:
        return "unavailable", 0, ["classification-is-not-git-root"]
    status_result = subprocess.run(
        ("git", "-C", str(repo), "status", "--porcelain=v1", "-z", "--untracked-files=normal"),
        capture_output=True,
        check=False,
        timeout=20,
    )
    if status_result.returncode != 0:
        return "unavailable", 0, ["git-status-unavailable"]
    # No names leave this process. Rename/copy records can contain two NUL
    # fields, so this count is deliberately a conservative metadata count.
    dirty_count = len([item for item in status_result.stdout.split(b"\0") if item])
    return ("dirty" if dirty_count else "clean"), dirty_count, []


def read_lock(repo: Path) -> tuple[dict[str, Any] | None, list[str]]:
    lock_path = repo / "copilot.lock.json"
    try:
        metadata = lock_path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            return None, ["lock-symlinked-or-special"]
        payload = json.loads(lock_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, []
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None, ["lock-unreadable-or-invalid"]
    if not isinstance(payload, dict) or not isinstance(payload.get("components"), list):
        return None, ["lock-schema-ambiguous"]
    return payload, []


def installed_families(repo: Path, lock: dict[str, Any] | None) -> list[str]:
    families: set[str] = set()
    if lock:
        for component in lock.get("components", []):
            if isinstance(component, dict) and component.get("component") in COMPONENT_FAMILIES:
                families.add(str(component["component"]))
    for family, marker in (("claude", ".claude"), ("codex", ".codex")):
        try:
            (repo / marker).lstat()
        except OSError:
            continue
        families.add(family)
    return sorted(families)


def component_family(repo: Path) -> list[str]:
    name = repo.name
    for family in COMPONENT_FAMILIES:
        if name == f"{family}-copilot" or name.startswith(f"{family}-copilot-"):
            return [family]
    return []


def checksum_state(repo: Path, lock: dict[str, Any] | None) -> tuple[str, int, int, list[str]]:
    if lock is None:
        markers = any((repo / item).exists() or (repo / item).is_symlink() for item in (".claude", ".codex"))
        return ("unknown" if markers else "not-applicable"), 0, 0, []
    mismatched = 0
    missing = 0
    ambiguity: list[str] = []
    checked = 0
    for component in lock.get("components", []):
        if not isinstance(component, dict) or not isinstance(component.get("files"), list):
            ambiguity.append("lock-component-invalid")
            continue
        for item in component["files"]:
            if not isinstance(item, dict) or item.get("ownership") != "framework":
                continue
            relative_value = item.get("path")
            expected = item.get("checksum")
            if not isinstance(relative_value, str) or not isinstance(expected, str):
                ambiguity.append("lock-file-entry-invalid")
                continue
            relative = Path(relative_value)
            if relative.is_absolute() or ".." in relative.parts:
                ambiguity.append("lock-path-unsafe")
                continue
            target = repo / relative
            checked += 1
            try:
                metadata = target.lstat()
            except FileNotFoundError:
                missing += 1
                continue
            except OSError:
                ambiguity.append("managed-file-unreadable")
                continue
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                ambiguity.append("managed-file-symlinked-or-special")
                continue
            try:
                actual = "sha256:" + hashlib.sha256(target.read_bytes()).hexdigest()
            except OSError:
                ambiguity.append("managed-file-unreadable")
                continue
            if actual != expected:
                mismatched += 1
    if ambiguity:
        state = "unknown"
    elif mismatched:
        state = "detected"
    elif checked:
        state = "not-detected"
    else:
        state = "unknown"
    return state, mismatched, missing, sorted(set(ambiguity))


def digest(value: Any) -> str:
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def census_identity(payload: dict[str, Any]) -> str:
    identity = copy.deepcopy(payload)
    identity["census_id"] = None
    identity["approval"] = {
        "status": "pending",
        "responsible_actor": "product-owner",
        "requested_at": None,
        "approved_census_id": None,
    }
    identity["summary"]["approved"] = 0
    identity["summary"]["authorized_mutations"] = 0
    for repository in identity["repositories"]:
        repository["approval_status"] = "pending"
    return digest(identity)


def read_entitlement_ledger(
    path: Path | None,
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    if path is None:
        return {}, {
            "kind": "machine-local-entitlement-ledger",
            "state": "unavailable",
            "receipt": None,
        }
    try:
        metadata = path.lstat()
        if (
            stat.S_ISLNK(metadata.st_mode)
            or not stat.S_ISREG(metadata.st_mode)
            or metadata.st_mode & 0o077
        ):
            return {}, {
                "kind": "machine-local-entitlement-ledger",
                "state": "invalid",
                "receipt": None,
            }
        raw = path.read_bytes()
        payload = json.loads(raw.decode("utf-8"))
        layers = payload.get("layers") if isinstance(payload, dict) else None
    except (FileNotFoundError, OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}, {
            "kind": "machine-local-entitlement-ledger",
            "state": "unavailable",
            "receipt": None,
        }
    if not isinstance(layers, dict):
        return {}, {
            "kind": "machine-local-entitlement-ledger",
            "state": "invalid",
            "receipt": None,
        }
    records = {
        str(layer_id): dict(record)
        for layer_id, record in layers.items()
        if isinstance(layer_id, str) and isinstance(record, dict)
    }
    return records, {
        "kind": "machine-local-entitlement-ledger",
        "state": "available",
        "receipt": "sha256:" + hashlib.sha256(raw).hexdigest(),
    }


def inferred_role(layer_id: str) -> str | None:
    lowered = layer_id.lower()
    return next((role for role in PROTECTED_ROLES if role in lowered), None)


def entitlement_for_repository(
    *,
    families: list[str],
    records: dict[str, dict[str, Any]],
    dependency_pending: bool,
    observed_at: datetime,
) -> dict[str, Any]:
    evidence: list[dict[str, Any]] = []
    for layer_id, record in sorted(records.items()):
        product = record.get("product")
        role = inferred_role(layer_id)
        state = str(record.get("state", "unknown"))
        if product not in families or role is None:
            continue
        revision = record.get("revision")
        evidence.append(
            {
                "product_family": product,
                "layer_id": layer_id,
                "tier_role": role,
                "state": state
                if state
                in {
                    "entitled",
                    "offline",
                    "unentitled",
                    "revoked",
                    "signed-out",
                    "invalid-source",
                }
                else "unknown",
                "revision": revision
                if isinstance(revision, int) and not isinstance(revision, bool)
                else None,
                "binding_receipt": digest(
                    {
                        "layer": layer_id,
                        "product": product,
                        "role": role,
                        "repo_binding": digest(record.get("repo")),
                        "state": state,
                        "checked_at": record.get("checked_at"),
                        "last_entitled_at": record.get("last_entitled_at"),
                        "revision": revision,
                    }
                ),
            }
        )
    if dependency_pending:
        state = "dependency-pending"
    elif not families:
        state = "not-required"
    elif not evidence:
        state = "unknown"
    else:
        states = {item["state"] for item in evidence}
        state = entitlement_state_from_evidence(states, records, evidence, observed_at)
    return {"state": state, "evidence": evidence}


def entitlement_state_from_evidence(
    states: set[str],
    records: dict[str, dict[str, Any]],
    evidence: list[dict[str, Any]],
    observed_at: datetime,
) -> str:
    precedence = (
        "revoked",
        "unentitled",
        "signed-out",
        "invalid-source",
    )
    blocked = next((state for state in precedence if state in states), None)
    if blocked:
        return blocked
    if "unknown" in states:
        return "unknown"
    if "offline" in states:
        last_entitled: list[datetime] = []
        for item in evidence:
            if item["state"] != "offline":
                continue
            raw = records.get(item["layer_id"], {}).get("last_entitled_at")
            try:
                parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
                parsed = parsed.astimezone(timezone.utc)
            except (TypeError, ValueError):
                return "offline-unverified"
            if parsed > observed_at:
                return "offline-unverified"
            last_entitled.append(parsed)
        if not last_entitled:
            return "offline-unverified"
        return (
            "offline-cached"
            if all(observed_at <= value + timedelta(hours=72) for value in last_entitled)
            else "stale-entitlement"
        )
    return "entitled" if states == {"entitled"} else "unknown"


def parse_dependency(value: str) -> dict[str, Any]:
    task, separator, status = value.partition("=")
    if not separator or not task.startswith("TASK-") or status not in {"pending", "in_progress", "completed", "blocked"}:
        raise ValueError(f"invalid dependency declaration: {value}")
    return {"task": task, "status": status, "required_for_approval": True}


def collect(args: argparse.Namespace) -> dict[str, Any]:
    projects_root = exact_path(args.projects_root)
    classification_path = exact_path(args.classification)
    ledger_path = exact_path(args.entitlement_ledger) if args.entitlement_ledger else None
    dependencies = sorted((parse_dependency(value) for value in args.dependency), key=lambda item: item["task"])
    dependency_pending = any(item["required_for_approval"] and item["status"] != "completed" for item in dependencies)
    with classification_path.open("rb") as handle:
        classification = tomllib.load(handle)
    rows = classification.get("repos")
    if not isinstance(rows, list):
        raise ValueError("classification has no repos array")
    entitlement_records, entitlement_source = read_entitlement_ledger(ledger_path)
    observed_at = datetime.fromisoformat(args.observed_at.replace("Z", "+00:00")).astimezone(timezone.utc)
    repositories: list[dict[str, Any]] = []
    seen: set[Path] = set()
    for row in sorted(rows, key=lambda item: str(item.get("path", ""))):
        relative = Path(str(row.get("path", "")))
        if relative.is_absolute() or ".." in relative.parts or any(char in str(relative) for char in WILDCARD_CHARACTERS):
            raise ValueError(f"classification row is not an exact relative path: {relative}")
        repo = exact_path(projects_root / relative)
        if repo in seen:
            raise ValueError(f"duplicate repository path: {repo}")
        seen.add(repo)
        repo_class = str(row.get("class", ""))
        role = str(row.get("role", "none"))
        git, dirty_count, ambiguity = git_state(repo)
        lock, lock_ambiguity = read_lock(repo)
        customization, mismatched, missing, checksum_ambiguity = checksum_state(repo, lock)
        ambiguity = sorted(set(ambiguity + lock_ambiguity + checksum_ambiguity))
        families = component_family(repo) if repo_class == "COMPONENT" else installed_families(repo, lock)
        exclusions: list[dict[str, str]] = []
        if repo_class == "COMPONENT":
            exclusions.append({"code": "component-authoring-tree", "source": "classification", "reason": "Tier/component authoring trees are outside project fan-out."})
        elif repo_class not in SUPPORTED_CLASSES:
            exclusions.append({"code": "non-solution-class", "source": "classification", "reason": f"Classification {repo_class} is outside solution-project fan-out."})
        if git == "unavailable":
            exclusions.append({"code": "git-root-unavailable", "source": "census-safety", "reason": "The exact path is not a safe readable Git repository root."})
        if git == "dirty":
            exclusions.append({"code": "dirty-working-tree", "source": "census-safety", "reason": "Active work is held and must never be changed by fan-out."})
        if customization == "detected":
            exclusions.append({"code": "customized-managed-content", "source": "census-safety", "reason": "Framework-tracked bytes differ from the recorded checksum and require person review."})
        if ambiguity:
            exclusions.append({"code": "ambiguous-state", "source": "census-safety", "reason": "The collector could not prove a safe deterministic project state."})
        classification_excluded = any(
            item["source"] == "classification" for item in exclusions
        )
        if classification_excluded:
            proposed_kind = "none"
            actor = "none"
            reason = "; ".join(item["reason"] for item in exclusions)
        elif exclusions:
            proposed_kind = "hold"
            actor = "person" if git == "dirty" or customization == "detected" else "repository-owner"
            reason = "; ".join(item["reason"] for item in exclusions)
        elif dependency_pending:
            proposed_kind = "refresh-after-dependencies"
            actor = "delivery-owner"
            reason = "Refresh after TASK-295 and TASK-297 complete; no mutation plan or approval exists."
        else:
            proposed_kind = "canonical-reconcile"
            actor = "product-owner"
            reason = "Candidate is inspectable; an exact canonical plan and owner approval are still required."
        repositories.append(
            {
                "repo_identity": digest(["repository", str(repo)]),
                "repo_path": str(repo),
                "repo_class": repo_class,
                "tier_role": role,
                "product_families": families,
                "entitlement": (
                    {"state": "not-required", "evidence": []}
                    if proposed_kind == "none"
                    else entitlement_for_repository(
                        families=families,
                        records=entitlement_records,
                        dependency_pending=dependency_pending,
                        observed_at=observed_at,
                    )
                ),
                "workspace_state": {
                    "git": git,
                    "dirty_entry_count": dirty_count,
                    "customization": customization,
                    "mismatched_managed_count": mismatched,
                    "missing_managed_count": missing,
                    "ambiguity": bool(ambiguity),
                    "ambiguity_reasons": ambiguity,
                },
                "exclusions": exclusions,
                "eligible": False,
                "responsible_actor": actor,
                "proposed_operation": {"kind": proposed_kind, "plan": None},
                "reason": reason,
                "approval_status": "pending",
            }
        )
    counts = Counter(
        "excluded" if row["proposed_operation"]["kind"] == "none" else "held" if row["proposed_operation"]["kind"] == "hold" else "candidate"
        for row in repositories
    )
    payload: dict[str, Any] = {
        "schema_version": "1.1",
        "mode": "read-only",
        "status": "provisional" if dependency_pending else "approval-ready",
        "census_id": "",
        "observed_at": args.observed_at,
        "configured_roots": [str(projects_root)],
        "sources": {
            "classification": str(classification_path),
            "entitlement": entitlement_source,
        },
        "dependencies": dependencies,
        "approval": {"status": "pending", "responsible_actor": "product-owner", "requested_at": None, "approved_census_id": None},
        "privacy": {
            "content_captured": False,
            "secret_values_captured": False,
            "git_paths_captured": False,
            "machine_identity_captured": False,
            "note": "Exact repository roots are required; file names, Git remotes, branches, status paths, identities, tokens, and project content are not recorded.",
        },
        "summary": {
            "total": len(repositories),
            "candidate": counts["candidate"],
            "excluded": counts["excluded"],
            "held": counts["held"],
            "dirty": sum(row["workspace_state"]["git"] == "dirty" for row in repositories),
            "customized": sum(row["workspace_state"]["customization"] == "detected" for row in repositories),
            "ambiguous": sum(row["workspace_state"]["ambiguity"] for row in repositories),
            "approved": 0,
            "authorized_mutations": 0,
        },
        "repositories": repositories,
    }
    payload["census_id"] = census_identity(payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--projects-root", required=True)
    parser.add_argument("--classification", required=True)
    parser.add_argument("--entitlement-ledger")
    parser.add_argument("--dependency", action="append", default=[])
    parser.add_argument("--observed-at", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    payload = collect(args)
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = exact_path(args.output)
        output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
