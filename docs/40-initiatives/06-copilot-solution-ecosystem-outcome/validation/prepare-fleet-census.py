#!/usr/bin/env python3
"""Bind a provisional fleet census to one fresh canonical reconciliation plan."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

PLAN_ID = re.compile(r"^plan_[0-9a-f]{32}$")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
SUPPORTED_COMPONENTS = frozenset({"claude", "codex"})
PLANNABLE_ROUTES = frozenset({"ready", "safe-setup-available", "safe-update-available"})


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
    return digest(identity)


def operation_binding(repo_identity: str, plan: dict[str, Any]) -> str:
    return digest({"repo_identity": repo_identity, "plan_id": plan["plan_id"], "plan_fingerprint": plan["plan_fingerprint"], "expires_at": plan["expires_at"], "target_paths": plan["target_paths"]})


def selected_rows(census: dict[str, Any]) -> list[dict[str, Any]]:
    rows = [row for row in census["repositories"] if row["proposed_operation"]["kind"] == "canonical-reconcile"]
    if any(row["exclusions"] for row in rows):
        raise ValueError("an excluded repository entered canonical planning")
    return rows


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


def prepare(census: dict[str, Any], plan_report: dict[str, Any], plan_record: dict[str, Any]) -> dict[str, Any]:
    if census.get("status") != "provisional" or any(item.get("status") != "completed" for item in census.get("dependencies", [])):
        raise ValueError("only a dependency-complete provisional census can be prepared")
    plan_id = plan_report.get("plan_id")
    expires_at = plan_report.get("expires_at")
    plan_fingerprint = plan_record.get("fresh_plan_fingerprint")
    if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id) or plan_record.get("plan_id") != plan_id:
        raise ValueError("canonical plan identity is invalid")
    if not isinstance(plan_fingerprint, str) or not DIGEST.fullmatch(plan_fingerprint):
        raise ValueError("canonical plan fingerprint is invalid")
    if not isinstance(expires_at, str) or plan_record.get("expires_at") != expires_at:
        raise ValueError("canonical plan expiration is invalid")
    public_plans = plan_report.get("plans")
    if not isinstance(public_plans, list) or plan_record.get("plans") != public_plans:
        raise ValueError("public and private canonical plans do not match")
    plans_by_path = {item.get("path"): item for item in public_plans if isinstance(item, dict)}
    expected_paths = [row["repo_path"] for row in selected_rows(census)]
    if list(plans_by_path) != expected_paths:
        raise ValueError("canonical plan paths do not match the census candidates")
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
    parser.add_argument("--request-output", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    census = load_json(Path(args.census))
    assessment = run_json((args.cc, "reconcile", "assess", "--json"))
    routed_census = apply_assessment(census, assessment)
    request = build_request(routed_census)
    with tempfile.TemporaryDirectory(prefix="copilot-fleet-census-") as temporary:
        request_path = Path(temporary) / "request.json"
        request_path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        plan_report = run_json((args.cc, "reconcile", "plan", "--request", str(request_path), "--json"))
    plan_id = plan_report.get("plan_id")
    if not isinstance(plan_id, str) or not PLAN_ID.fullmatch(plan_id):
        raise RuntimeError("canonical reconciliation did not issue an exact plan")
    plan_record = load_json(Path(args.plan_store_root) / "plans" / f"{plan_id}.json")
    prepared = prepare(routed_census, plan_report, plan_record)
    Path(args.request_output).write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    Path(args.output).write_text(json.dumps(prepared, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"census_id": prepared["census_id"], "plan_id": plan_id, "expires_at": plan_report["expires_at"], "summary": prepared["summary"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
