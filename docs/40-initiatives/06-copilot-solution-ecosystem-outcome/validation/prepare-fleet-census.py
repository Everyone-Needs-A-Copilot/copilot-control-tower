#!/usr/bin/env python3
"""Bind a provisional fleet census to one fresh canonical reconciliation plan."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PLAN_ID = re.compile(r"^plan_[0-9a-f]{32}$")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
SUPPORTED_COMPONENTS = frozenset({"claude", "codex"})
PLANNABLE_ROUTES = frozenset({"ready", "safe-setup-available", "safe-update-available"})
BATCH_SELECTION_KEYS = frozenset({"census_id", "repositories"})
BATCH_REPOSITORY_KEYS = frozenset({"repo_identity", "repo_path"})
EXACT_HERMES_PATHS = frozenset(
    {
        "/Volumes/Dev/Sites/TSM/_archive/h1",
        "/Volumes/Dev/Sites/TSM/h2",
        "/Volumes/Dev/Sites/TSM/h3",
        "/Volumes/Dev/Sites/TSM/hermes",
    }
)
ELIGIBLE_REPO_CLASSES = frozenset({"PRODUCT", "SITE-CONTENT"})


def digest(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def census_identity(payload: dict[str, Any]) -> str:
    identity = copy.deepcopy(payload)
    identity["census_id"] = None
    identity["approval"] = {"status": "pending", "responsible_actor": "product-owner", "requested_at": None, "approved_census_id": None}
    identity["summary"]["approved"] = 0
    identity["summary"]["authorized_mutations"] = 0
    for repository in identity["repositories"]:
        repository["approval_status"] = "pending"
        repository["eligible"] = False
    return digest(identity)


def operation_binding(repo_identity: str, plan: dict[str, Any]) -> str:
    return digest({"repo_identity": repo_identity, "plan_id": plan["plan_id"], "plan_fingerprint": plan["plan_fingerprint"], "expires_at": plan["expires_at"], "target_paths": plan["target_paths"]})


def private_plan_binding(
    request_fingerprint: str,
    plan_fingerprint: str,
    helper_version: str,
    schema_version: str,
) -> str:
    return digest(
        {
            "request_fingerprint": request_fingerprint,
            "fresh_plan_fingerprint": plan_fingerprint,
            "helper_version": helper_version,
            "schema_version": schema_version,
        }
    )


def _timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def selected_rows(census: dict[str, Any]) -> list[dict[str, Any]]:
    rows = [row for row in census["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile"]
    if any(row["exclusions"] for row in rows):
        raise ValueError("an excluded repository entered canonical planning")
    return rows


def _canonical_path(value: Any) -> str | None:
    if not isinstance(value, str) or not value.startswith("/"):
        return None
    if any(character in value for character in "*?[]{}"):
        return None
    parts = value.split("/")[1:]
    if any(part in {"", ".", ".."} for part in parts) or str(Path(value)) != value:
        return None
    return value


def _load_validator():
    path = Path(__file__).with_name("validate-fleet-census.py")
    spec = importlib.util.spec_from_file_location("fleet_census_preparation_validator", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the fleet census validator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _candidate_is_safe(row: dict[str, Any]) -> bool:
    path = row.get("repo_path")
    workspace = row.get("workspace_state")
    return bool(
        isinstance(path, str)
        and path not in EXACT_HERMES_PATHS
        and row.get("repo_identity") == digest(["repository", path])
        and row.get("repo_class") in ELIGIBLE_REPO_CLASSES
        and row.get("tier_role") == "none"
        and row.get("exclusions") == []
        and row.get("approval_status") == "pending"
        and row.get("eligible") is False
        and isinstance(workspace, dict)
        and workspace.get("git") == "clean"
        and workspace.get("customization") == "not-detected"
        and workspace.get("ambiguity") is False
        and row.get("proposed_operation") == {"kind": "canonical-reconcile", "plan": None}
    )


def select_batch(census: dict[str, Any], selection: dict[str, Any]) -> dict[str, Any]:
    """Hold every candidate outside one exact pre-plan pilot or fan-out batch."""

    if set(selection) != BATCH_SELECTION_KEYS:
        raise ValueError("batch selection must contain only census_id and repositories")
    if selection.get("census_id") != census.get("census_id"):
        raise ValueError("batch selection is not bound to the provisional census identity")
    repositories = selection.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ValueError("batch selection must contain at least one exact repository")
    selected: dict[str, str] = {}
    paths: set[str] = set()
    ordered_paths: list[str] = []
    for index, row in enumerate(repositories):
        if not isinstance(row, dict) or set(row) != BATCH_REPOSITORY_KEYS:
            raise ValueError(f"batch selection repository {index} is not an exact identity/path pair")
        identity = row.get("repo_identity")
        path = _canonical_path(row.get("repo_path"))
        if not isinstance(identity, str) or path is None:
            raise ValueError(f"batch selection repository {index} has an invalid identity or path")
        if identity in selected or path in paths:
            raise ValueError("batch selection contains a duplicate repository")
        selected[identity] = path
        paths.add(path)
        ordered_paths.append(path)
    if ordered_paths != sorted(ordered_paths):
        raise ValueError("batch selection repositories must be sorted by exact path")

    candidates = {row["repo_identity"]: row for row in census["repositories"] if _candidate_is_safe(row)}
    if set(selected) - set(candidates):
        raise ValueError("batch selection contains a held, excluded, or unknown repository")
    for identity, path in selected.items():
        if candidates[identity]["repo_path"] != path:
            raise ValueError("batch selection repository identity/path binding does not match")

    prepared = copy.deepcopy(census)
    for row in prepared["repositories"]:
        if (
            row["proposed_operation"]["kind"] == "canonical-reconcile"
            and row["repo_identity"] not in selected
        ):
            row["exclusions"].append(
                {
                    "code": "owner-batch-deferred",
                    "source": "census-safety",
                    "reason": "This candidate is outside the exact pre-plan batch and remains unmodified.",
                }
            )
            row["proposed_operation"] = {"kind": "hold", "plan": None}
            row["responsible_actor"] = "product-owner"
            row["reason"] = "Regenerate a fresh exact batch plan before this repository can receive mutation authority."
    return prepared


def apply_assessment(census: dict[str, Any], assessment: dict[str, Any]) -> dict[str, Any]:
    projects = assessment.get("projects")
    if not isinstance(projects, list):
        raise ValueError("canonical assessment has no project census")
    routes = {item.get("path"): item.get("route") for item in projects if isinstance(item, dict)}
    prepared = copy.deepcopy(census)
    for row in selected_rows(prepared):
        route = routes.get(row["repo_path"])
        if route in PLANNABLE_ROUTES:
            continue
        route_code = route if isinstance(route, str) and re.fullmatch(r"[a-z0-9-]+", route) else "not-assessed"
        row["exclusions"].append({"code": f"canonical-route-{route_code}", "source": "census-safety", "reason": f"Canonical assessment route {route_code} is not eligible for automatic planning."})
        row["proposed_operation"] = {"kind": "hold", "plan": None}
        row["responsible_actor"] = "person" if route == "excluded" else "repository-owner"
        row["reason"] = "A person must resolve the canonical assessment route before this repository can enter fleet mutation."
    return prepared


def build_request(census: dict[str, Any]) -> dict[str, Any]:
    projects = []
    for row in selected_rows(census):
        components = sorted(SUPPORTED_COMPONENTS.intersection(row["product_families"]))
        if not components:
            raise ValueError(f"candidate has no supported project component: {row['repo_path']}")
        projects.append({"path": row["repo_path"], "components": components})
    if not projects:
        raise ValueError("census has no canonical planning candidates")
    return {"schema_version": "1.0", "roots": list(census["configured_roots"]), "projects": projects}


def exact_targets(repo_path: str, operations: list[dict[str, Any]]) -> list[str]:
    repo = Path(repo_path)
    targets: set[str] = set()
    for operation in operations:
        target = operation.get("target")
        if not isinstance(target, str):
            raise ValueError(f"canonical operation lacks a target for {repo_path}")
        relative = Path(target)
        if relative.is_absolute() or any(part in {"", ".", ".."} for part in relative.parts):
            raise ValueError(f"canonical operation target is unsafe for {repo_path}")
        absolute = Path(os.path.abspath(repo / relative))
        try:
            absolute.relative_to(repo)
        except ValueError as exc:
            raise ValueError(f"canonical operation target escapes {repo_path}") from exc
        targets.add(str(absolute))
    return sorted(targets)


def prepare(
    census: dict[str, Any],
    plan_report: dict[str, Any],
    plan_record: dict[str, Any],
    *,
    now_utc: datetime | None = None,
) -> dict[str, Any]:
    captured_now = now_utc or datetime.now(timezone.utc)
    if captured_now.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    captured_now = captured_now.astimezone(timezone.utc)
    if census.get("status") != "provisional" or any(item.get("status") != "completed" for item in census.get("dependencies", [])):
        raise ValueError("only a dependency-complete provisional census can be prepared")
    plan_id = plan_report.get("plan_id")
    expires_at = plan_report.get("expires_at")
    plan_fingerprint = plan_record.get("fresh_plan_fingerprint")
    if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id) or plan_record.get("plan_id") != plan_id:
        raise ValueError("canonical plan identity is invalid")
    if not isinstance(plan_fingerprint, str) or not DIGEST.fullmatch(plan_fingerprint):
        raise ValueError("canonical plan fingerprint is invalid")
    expiration = _timestamp(expires_at)
    created_at = _timestamp(plan_record.get("created_at"))
    if (
        not isinstance(expires_at, str)
        or plan_record.get("expires_at") != expires_at
        or expiration is None
        or expiration <= captured_now
        or created_at is None
        or created_at > captured_now
        or created_at >= expiration
    ):
        raise ValueError("canonical plan expiration is invalid")
    if (
        plan_record.get("storage_schema_version") != "1.0"
        or plan_record.get("state") != "reviewed"
        or plan_record.get("claim_token_hash") is not None
        or plan_record.get("outcome") is not None
        or plan_record.get("finished_at") is not None
    ):
        raise ValueError("private canonical plan is not fresh and unclaimed")
    expected_request = build_request(census)
    request_fingerprint = digest(expected_request)
    helper_version = plan_record.get("helper_version")
    schema_version = plan_record.get("schema_version")
    if (
        plan_record.get("canonical_request") != expected_request
        or plan_record.get("request_fingerprint") != request_fingerprint
        or not isinstance(helper_version, str)
        or not helper_version
        or not isinstance(schema_version, str)
        or not schema_version
        or plan_record.get("binding_fingerprint")
        != private_plan_binding(
            request_fingerprint,
            plan_fingerprint,
            helper_version,
            schema_version,
        )
    ):
        raise ValueError("private canonical plan binding is invalid")
    public_plans = plan_report.get("plans")
    if not isinstance(public_plans, list) or plan_record.get("plans") != public_plans:
        raise ValueError("public and private canonical plans do not match")
    if not all(isinstance(item, dict) and isinstance(item.get("path"), str) for item in public_plans):
        raise ValueError("canonical plan contains an invalid project record")
    public_paths = [item["path"] for item in public_plans]
    expected_paths = [row["repo_path"] for row in selected_rows(census)]
    if public_paths != expected_paths or len(public_paths) != len(set(public_paths)):
        raise ValueError("canonical plan paths do not match the census candidates")
    plans_by_path = {item["path"]: item for item in public_plans}
    prepared = copy.deepcopy(census)
    for row in prepared["repositories"]:
        if row["repo_path"] not in plans_by_path:
            continue
        operations = plans_by_path[row["repo_path"]].get("operations")
        if not isinstance(operations, list):
            raise ValueError(f"canonical plan operations are invalid for {row['repo_path']}")
        targets = exact_targets(row["repo_path"], operations)
        plan = {"plan_id": plan_id, "plan_fingerprint": plan_fingerprint, "expires_at": expires_at, "target_paths": targets, "binding_id": ""}
        plan["binding_id"] = operation_binding(row["repo_identity"], plan)
        if targets:
            row["proposed_operation"] = {"kind": "canonical-reconcile", "plan": plan}
            row["responsible_actor"] = "product-owner"
            row["reason"] = f"Canonical reconciliation proposes {len(targets)} exact target path(s); owner approval is required."
        else:
            row["proposed_operation"] = {"kind": "canonical-no-change", "plan": plan}
            row["responsible_actor"] = "none"
            row["reason"] = "Canonical reconciliation verified that no project mutation is needed."
    prepared["status"] = "approval-ready"
    counts = Counter(row["proposed_operation"]["kind"] for row in prepared["repositories"])
    prepared["summary"] = {
        "total": len(prepared["repositories"]),
        "candidate": counts["canonical-reconcile"],
        "no_change": counts["canonical-no-change"],
        "excluded": counts["none"],
        "held": counts["hold"],
        "dirty": sum(row["workspace_state"]["git"] == "dirty" for row in prepared["repositories"]),
        "customized": sum(row["workspace_state"]["customization"] == "detected" for row in prepared["repositories"]),
        "ambiguous": sum(row["workspace_state"]["ambiguity"] for row in prepared["repositories"]),
        "approved": 0,
        "authorized_mutations": 0,
    }
    prepared["census_id"] = census_identity(prepared)
    return prepared


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def run_json(command: tuple[str, ...], *, timeout: int = 300) -> dict[str, Any]:
    result = subprocess.run(command, capture_output=True, text=True, check=False, timeout=timeout)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"canonical reconciliation did not return JSON (exit {result.returncode})") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("canonical reconciliation returned a non-object report")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("census")
    parser.add_argument("--cc", required=True)
    parser.add_argument("--plan-store-root", required=True)
    parser.add_argument("--batch-selection", required=True)
    parser.add_argument("--schema", default=str(Path(__file__).with_name("fleet-census.schema.json")))
    parser.add_argument("--request-output", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    captured_now = datetime.now(timezone.utc)
    census = load_json(Path(args.census))
    schema = load_json(Path(args.schema))
    validator = _load_validator()
    input_errors = validator.validate(census, schema, now_utc=captured_now)
    if input_errors:
        raise ValueError("input census is invalid: " + "; ".join(input_errors))
    assessment = run_json((args.cc, "reconcile", "assess", "--json"))
    routed_census = apply_assessment(census, assessment)
    batched_census = select_batch(routed_census, load_json(Path(args.batch_selection)))
    request = build_request(batched_census)
    with tempfile.TemporaryDirectory(prefix="copilot-fleet-census-") as temporary:
        request_path = Path(temporary) / "request.json"
        request_path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        plan_report = run_json((args.cc, "reconcile", "plan", "--request", str(request_path), "--json"))
    plan_id = plan_report.get("plan_id")
    if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id):
        raise RuntimeError("canonical reconciliation did not issue an exact plan")
    plan_record = load_json(Path(args.plan_store_root) / "plans" / f"{plan_id}.json")
    prepared = prepare(batched_census, plan_report, plan_record, now_utc=captured_now)
    output_errors = validator.validate(prepared, schema, now_utc=captured_now)
    if output_errors:
        raise ValueError("approval-ready census is invalid: " + "; ".join(output_errors))
    Path(args.request_output).write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    Path(args.output).write_text(json.dumps(prepared, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"census_id": prepared["census_id"], "plan_id": plan_id, "expires_at": plan_report["expires_at"], "summary": prepared["summary"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
