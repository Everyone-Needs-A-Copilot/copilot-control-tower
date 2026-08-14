#!/usr/bin/env python3
"""Validate fleet-census schema plus mutation-authority semantics."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import posixpath
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

WILDCARD_CHARACTERS = frozenset("*?[]{}")
IDENTITY_KEYS = frozenset(
    {"login", "token", "username", "user", "identity", "entitlement_ledger"}
)
REQUIRED_DEPENDENCIES = frozenset({"TASK-281", "TASK-295", "TASK-297"})
ALLOWED_ABSOLUTE_PATH_LOCATIONS = (
    re.compile(r"^\$\.configured_roots\[[0-9]+\]$"),
    re.compile(r"^\$\.sources\.classification$"),
    re.compile(r"^\$\.repositories\[[0-9]+\]\.repo_path$"),
    re.compile(
        r"^\$\.repositories\[[0-9]+\]\.proposed_operation\.plan"
        r"\.target_paths\[[0-9]+\]$"
    ),
)
IDENTITY_VALUE_PATTERN = re.compile(
    r"(?i)(?:\b(?:login|username|token)\s*[:=]\s*\S+|"
    r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b)"
)


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
        repository["eligible"] = False
    return digest(identity)


def operation_binding(repo_identity: str, plan: dict[str, Any]) -> str:
    return digest(
        {
            "repo_identity": repo_identity,
            "plan_id": plan["plan_id"],
            "plan_fingerprint": plan["plan_fingerprint"],
            "expires_at": plan["expires_at"],
            "target_paths": plan["target_paths"],
        }
    )


def _contains(root: Path, target: Path) -> bool:
    try:
        target.relative_to(root)
        return True
    except ValueError:
        return False


def _canonical_absolute_path(value: Any) -> Path | None:
    if not isinstance(value, str) or not value.startswith("/"):
        return None
    if any(part in {"", ".", ".."} for part in value.split("/")[1:]):
        return None
    if posixpath.normpath(value) != value:
        return None
    return Path(value)


def _absolute_path_allowed(location: str) -> bool:
    return any(pattern.fullmatch(location) for pattern in ALLOWED_ABSOLUTE_PATH_LOCATIONS)


def _scan_identity_leaks(value: Any, location: str = "$") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            lowered = str(key).lower()
            if lowered in IDENTITY_KEYS:
                errors.append(f"{location}.{key}: prohibited identity/secret field")
            errors.extend(_scan_identity_leaks(item, f"{location}.{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            errors.extend(_scan_identity_leaks(item, f"{location}[{index}]"))
    elif isinstance(value, str):
        lowered = value.lower()
        if (
            "/users/" in lowered
            or "/home/" in lowered
            or "ghp_" in lowered
            or "github_pat_" in lowered
            or "bearer " in lowered
            or IDENTITY_VALUE_PATTERN.search(value)
        ):
            errors.append(f"{location}: machine identity or credential-like value")
        elif value.startswith("/") and not _absolute_path_allowed(location):
            errors.append(f"{location}: machine-local absolute path is prohibited")
    return errors


def _expiration(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def semantic_errors(payload: dict[str, Any], *, now_utc: datetime | None = None) -> list[str]:
    captured_now = now_utc or datetime.now(timezone.utc)
    if captured_now.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    captured_now = captured_now.astimezone(timezone.utc)
    errors = _scan_identity_leaks(payload)
    repositories = payload.get("repositories")
    if not isinstance(repositories, list):
        return [*errors, "$.repositories: must be an array"]
    paths = [row.get("repo_path") for row in repositories if isinstance(row, dict)]
    identities = [
        row.get("repo_identity") for row in repositories if isinstance(row, dict)
    ]
    if paths != sorted(paths):
        errors.append("$.repositories: repository paths must be sorted")
    if len(paths) != len(set(paths)):
        errors.append("$.repositories: duplicate repository path")
    if len(identities) != len(set(identities)):
        errors.append("$.repositories: duplicate repository identity")
    roots: list[Path] = []
    for index, value in enumerate(payload.get("configured_roots", [])):
        root = _canonical_absolute_path(value)
        if root is None:
            errors.append(f"$.configured_roots[{index}]: path is not canonical")
        else:
            roots.append(root)
    approval_ready_plan_identities: set[tuple[Any, Any, Any]] = set()
    for index, row in enumerate(repositories):
        location = f"$.repositories[{index}]"
        if not isinstance(row, dict):
            errors.append(f"{location}: must be an object")
            continue
        repo_path = row.get("repo_path")
        if not isinstance(repo_path, str):
            continue
        repo = _canonical_absolute_path(repo_path)
        if repo is None:
            errors.append(f"{location}.repo_path: path is not canonical")
            continue
        if any(character in repo_path for character in WILDCARD_CHARACTERS):
            errors.append(f"{location}.repo_path: wildcard is prohibited")
        if not any(_contains(root, repo) for root in roots):
            errors.append(f"{location}.repo_path: outside configured roots")
        expected_identity = digest(["repository", repo_path])
        if row.get("repo_identity") != expected_identity:
            errors.append(f"{location}.repo_identity: does not bind exact path")
        operation = row.get("proposed_operation")
        plan = operation.get("plan") if isinstance(operation, dict) else None
        operation_kind = operation.get("kind") if isinstance(operation, dict) else None
        if plan is not None:
            if payload.get("status") == "approval-ready":
                approval_ready_plan_identities.add(
                    (
                        plan.get("plan_id"),
                        plan.get("plan_fingerprint"),
                        plan.get("expires_at"),
                    )
                )
                expiration = _expiration(plan.get("expires_at"))
                if expiration is None:
                    errors.append(f"{location}.proposed_operation.plan: invalid expiration")
                elif expiration <= captured_now:
                    errors.append(f"{location}.proposed_operation.plan: canonical plan expired")
            targets = plan.get("target_paths", [])
            if targets != sorted(targets) or len(targets) != len(set(targets)):
                errors.append(f"{location}.proposed_operation.plan: targets not sorted/unique")
            for target in targets:
                canonical_target = _canonical_absolute_path(target)
                if canonical_target is None or any(
                    character in target for character in WILDCARD_CHARACTERS
                ):
                    errors.append(f"{location}.proposed_operation.plan: invalid target")
                elif not _contains(repo, canonical_target) or canonical_target == repo:
                    errors.append(f"{location}.proposed_operation.plan: unbound target")
            if plan.get("binding_id") != operation_binding(
                str(row.get("repo_identity")), plan
            ):
                errors.append(f"{location}.proposed_operation.plan: binding mismatch")
            if operation_kind not in {"canonical-reconcile", "canonical-no-change"}:
                errors.append(f"{location}: held or excluded operation carries a plan")
        approved = row.get("approval_status") == "approved"
        if approved and (
            not row.get("eligible")
            or operation.get("kind") != "canonical-reconcile"
            or plan is None
        ):
            errors.append(f"{location}: approved row lacks eligibility/exact plan")
        workspace_state = row.get("workspace_state", {})
        unsafe_workspace = (
            workspace_state.get("git") in {"dirty", "unavailable"}
            or workspace_state.get("customization") == "detected"
            or workspace_state.get("ambiguity") is True
        )
        if unsafe_workspace and operation_kind not in {"none", "hold"}:
            errors.append(f"{location}: unsafe workspace must remain held or excluded")
        if payload.get("status") == "approval-ready" and operation_kind == "refresh-after-dependencies":
            errors.append(f"{location}: approval-ready census contains an unresolved operation")
        if operation_kind in {"canonical-reconcile", "canonical-no-change"} and plan is None and payload.get("status") == "approval-ready":
            errors.append(f"{location}: canonical reconcile lacks exact plan")
        if operation_kind == "canonical-reconcile" and plan is not None and not plan.get("target_paths"):
            errors.append(f"{location}: canonical reconcile has no exact targets")
        if operation_kind == "canonical-no-change" and plan is not None and plan.get("target_paths"):
            errors.append(f"{location}: canonical no-change carries mutation targets")
        if row.get("eligible") != approved:
            errors.append(f"{location}: eligibility and row approval are inconsistent")
    if payload.get("status") == "approval-ready" and len(approval_ready_plan_identities) > 1:
        errors.append("$.repositories: approval-ready rows do not share one canonical plan identity")
    if payload.get("census_id") != census_identity(payload):
        errors.append("$.census_id: does not match semantic census identity")
    expected_summary = Counter()
    for row in repositories:
        kind = row["proposed_operation"]["kind"]
        if kind == "none":
            expected_summary["excluded"] += 1
        elif kind == "hold":
            expected_summary["held"] += 1
        elif kind == "canonical-no-change":
            expected_summary["no_change"] += 1
        else:
            expected_summary["candidate"] += 1
    summary = payload.get("summary", {})
    recomputed = {
        "total": len(repositories),
        "candidate": expected_summary["candidate"],
        "excluded": expected_summary["excluded"],
        "held": expected_summary["held"],
        "dirty": sum(row["workspace_state"]["git"] == "dirty" for row in repositories),
        "customized": sum(
            row["workspace_state"]["customization"] == "detected"
            for row in repositories
        ),
        "ambiguous": sum(row["workspace_state"]["ambiguity"] for row in repositories),
        "approved": sum(row["approval_status"] == "approved" for row in repositories),
        "authorized_mutations": sum(
            row["approval_status"] == "approved"
            and row["eligible"]
            and row["proposed_operation"]["kind"] == "canonical-reconcile"
            and row["proposed_operation"]["plan"] is not None
            for row in repositories
        ),
    }
    if expected_summary["no_change"] or "no_change" in summary:
        recomputed["no_change"] = expected_summary["no_change"]
    if summary != recomputed:
        errors.append("$.summary: does not match repository dispositions")
    dependencies = payload.get("dependencies", [])
    dependency_tasks = [item.get("task") for item in dependencies]
    if set(dependency_tasks) != REQUIRED_DEPENDENCIES or len(dependency_tasks) != len(
        REQUIRED_DEPENDENCIES
    ):
        errors.append("$.dependencies: exact TASK-281/TASK-295/TASK-297 set required")
    if any(item.get("required_for_approval") is not True for item in dependencies):
        errors.append("$.dependencies: required dependencies cannot be downgraded")
    required_incomplete = any(
        item.get("task") in REQUIRED_DEPENDENCIES
        and item.get("status") != "completed"
        for item in dependencies
    )
    approval = payload.get("approval", {})
    if payload.get("status") == "provisional":
        if approval.get("status") != "pending":
            errors.append("$.approval: provisional census must remain pending")
        if any(row.get("approval_status") != "pending" for row in repositories):
            errors.append("$.repositories: provisional rows must remain pending")
        if any(
            row.get("eligible") or row.get("proposed_operation", {}).get("plan")
            for row in repositories
        ):
            errors.append("$.repositories: provisional census cannot carry mutation authority")
    if payload.get("status") == "approval-ready" and required_incomplete:
        errors.append("$.dependencies: approval-ready requires completed dependencies")
    row_authority = any(
        row.get("approval_status") == "approved" or row.get("eligible")
        for row in repositories
    )
    reported_authority = summary.get("authorized_mutations", 0) != 0
    if payload.get("status") == "superseded" and (
        approval.get("status") == "approved" or row_authority or reported_authority
    ):
        errors.append("$: superseded census cannot carry mutation authority")
    if (row_authority or reported_authority) and approval.get("status") != "approved":
        errors.append("$.approval: row authority requires global owner approval")
    if approval.get("status") == "approved":
        if required_incomplete:
            errors.append("$.approval: required dependency incomplete")
        if not approval.get("requested_at"):
            errors.append("$.approval: approved census lacks request timestamp")
        if approval.get("approved_census_id") != payload.get("census_id"):
            errors.append("$.approval: approval is not bound to census identity")
        if any(row.get("approval_status") == "pending" for row in repositories):
            errors.append("$.repositories: globally approved census has pending rows")
        if (
            summary.get("approved") != summary.get("candidate")
            or summary.get("authorized_mutations") != summary.get("candidate")
        ):
            errors.append(
                "$.approval: approved authority must cover the complete canonical batch plan"
            )
    elif approval.get("approved_census_id") is not None:
        errors.append("$.approval: unapproved census carries approved identity")
    return errors


def validate(
    payload: dict[str, Any],
    schema: dict[str, Any],
    *,
    now_utc: datetime | None = None,
) -> list[str]:
    captured_now = now_utc or datetime.now(timezone.utc)
    try:
        import jsonschema
    except ImportError as exc:  # pragma: no cover - environment prerequisite
        raise RuntimeError("jsonschema is required for fleet census validation") from exc
    validator = jsonschema.Draft202012Validator(
        schema, format_checker=jsonschema.FormatChecker()
    )
    schema_errors = [
        f"{'.'.join(str(item) for item in error.absolute_path) or '$'}: {error.message}"
        for error in sorted(validator.iter_errors(payload), key=lambda item: list(item.absolute_path))
    ]
    return [*schema_errors, *semantic_errors(payload, now_utc=captured_now)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report")
    parser.add_argument("--schema", default=str(Path(__file__).with_name("fleet-census.schema.json")))
    args = parser.parse_args()
    payload = json.loads(Path(args.report).read_text(encoding="utf-8"))
    schema = json.loads(Path(args.schema).read_text(encoding="utf-8"))
    errors = validate(payload, schema)
    if errors:
        for error in errors:
            print(error)
        return 1
    print(f"fleet census valid: {len(payload['repositories'])} exact repositories; mutation authority={payload['summary']['authorized_mutations']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
