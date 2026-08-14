#!/usr/bin/env python3
"""Record an exact owner decision for one unexpired fleet census."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

EXACT_HERMES_PATHS = frozenset(
    {
        "/Volumes/Dev/Sites/TSM/_archive/h1",
        "/Volumes/Dev/Sites/TSM/h2",
        "/Volumes/Dev/Sites/TSM/h3",
        "/Volumes/Dev/Sites/TSM/hermes",
    }
)
SELECTION_KEYS = frozenset({"census_id", "plan", "repositories"})
SELECTION_PLAN_KEYS = frozenset({"plan_id", "plan_fingerprint", "expires_at"})
SELECTION_REPOSITORY_KEYS = frozenset(
    {"repo_identity", "repo_path", "target_paths"}
)


def _load_validator():
    path = Path(__file__).with_name("validate-fleet-census.py")
    spec = importlib.util.spec_from_file_location("fleet_census_approval_validator", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the fleet census validator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def _canonical_path(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value.startswith("/"):
        raise ValueError(f"{field} must be an exact absolute path")
    if any(character in value for character in "*?[]{}"):
        raise ValueError(f"{field} cannot contain a wildcard")
    parts = value.split("/")[1:]
    if any(part in {"", ".", ".."} for part in parts):
        raise ValueError(f"{field} must be a canonical path")
    if str(Path(value)) != value:
        raise ValueError(f"{field} must be a canonical path")
    return value


def _selection_rows(selection: dict[str, Any]) -> list[dict[str, Any]]:
    if set(selection) != SELECTION_KEYS:
        raise ValueError("selection must contain only census_id, plan, and repositories")
    plan = selection.get("plan")
    if not isinstance(plan, dict) or set(plan) != SELECTION_PLAN_KEYS:
        raise ValueError("selection plan must contain one exact canonical plan identity")
    repositories = selection.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ValueError("at least one repository must be explicitly selected")
    identities: set[str] = set()
    paths: set[str] = set()
    rows: list[dict[str, Any]] = []
    for index, row in enumerate(repositories):
        location = f"selection.repositories[{index}]"
        if not isinstance(row, dict) or set(row) != SELECTION_REPOSITORY_KEYS:
            raise ValueError(f"{location} must contain exact identity, path, and targets")
        identity = row.get("repo_identity")
        if not isinstance(identity, str):
            raise ValueError(f"{location}.repo_identity must be explicit")
        path = _canonical_path(row.get("repo_path"), field=f"{location}.repo_path")
        targets = row.get("target_paths")
        if not isinstance(targets, list) or not targets:
            raise ValueError(f"{location}.target_paths must be an explicit nonempty list")
        exact_targets = [
            _canonical_path(target, field=f"{location}.target_paths")
            for target in targets
        ]
        if exact_targets != sorted(exact_targets):
            raise ValueError(f"{location}.target_paths must be sorted")
        if len(exact_targets) != len(set(exact_targets)):
            raise ValueError(f"{location}.target_paths contains a duplicate")
        if identity in identities or path in paths:
            raise ValueError("selection contains a duplicate repository")
        identities.add(identity)
        paths.add(path)
        rows.append(row)
    if [row["repo_path"] for row in rows] != sorted(paths):
        raise ValueError("selected repositories must be sorted by exact path")
    return rows


def _plan_identity(census: dict[str, Any]) -> dict[str, Any]:
    identities: set[tuple[Any, Any, Any]] = set()
    for row in census["repositories"]:
        plan = row["proposed_operation"]["plan"]
        if plan is not None:
            identities.add(
                (plan["plan_id"], plan["plan_fingerprint"], plan["expires_at"])
            )
    if len(identities) != 1:
        raise ValueError("census does not carry one canonical plan identity")
    plan_id, plan_fingerprint, expires_at = identities.pop()
    return {
        "plan_id": plan_id,
        "plan_fingerprint": plan_fingerprint,
        "expires_at": expires_at,
    }


def _require_zero_authority(census: dict[str, Any]) -> None:
    approval = census.get("approval", {})
    summary = census.get("summary", {})
    rows = census.get("repositories", [])
    if (
        approval.get("status") != "pending"
        or approval.get("requested_at") is not None
        or approval.get("approved_census_id") is not None
        or summary.get("approved") != 0
        or summary.get("authorized_mutations") != 0
        or any(
            row.get("approval_status") != "pending" or row.get("eligible") is not False
            for row in rows
        )
    ):
        raise ValueError("input census contains hidden or prior mutation authority")


def decide(
    census: dict[str, Any],
    selection: dict[str, Any],
    schema: dict[str, Any],
    *,
    census_id: str,
    actor: str,
    decision: str,
    now_utc: datetime | None = None,
) -> dict[str, Any]:
    captured_now = now_utc or datetime.now(timezone.utc)
    if captured_now.tzinfo is None:
        raise ValueError("now_utc must be timezone-aware")
    captured_now = captured_now.astimezone(timezone.utc)
    validator = _load_validator()
    input_errors = validator.validate(census, schema, now_utc=captured_now)
    if input_errors:
        raise ValueError("input census is invalid: " + "; ".join(input_errors))
    if census.get("status") != "approval-ready":
        raise ValueError("only an approval-ready census can receive an owner decision")
    _require_zero_authority(census)
    if not isinstance(census_id, str) or census.get("census_id") != census_id:
        raise ValueError("explicit census ID does not match the reviewed census")
    if actor != "product-owner":
        raise ValueError("the explicit decision actor must be product-owner")
    if decision not in {"approved", "rejected"}:
        raise ValueError("decision must be approved or rejected")
    selected_rows = _selection_rows(selection)
    if selection.get("census_id") != census_id:
        raise ValueError("selection census ID does not match the reviewed census")
    if selection.get("plan") != _plan_identity(census):
        raise ValueError("selection plan identity does not match the reviewed census")

    rows_by_identity = {row["repo_identity"]: row for row in census["repositories"]}
    selected_identities: set[str] = set()
    for selection_row in selected_rows:
        identity = selection_row["repo_identity"]
        row = rows_by_identity.get(identity)
        if row is None:
            raise ValueError("selected repository identity is not in the census")
        if row["repo_path"] != selection_row["repo_path"]:
            raise ValueError("selected repository identity/path binding does not match")
        operation = row["proposed_operation"]
        if (
            row["repo_path"] in EXACT_HERMES_PATHS
            or row["exclusions"]
            or operation["kind"] in {"none", "hold"}
        ):
            raise ValueError("held, excluded, or Hermes repositories cannot be selected")
        if operation["kind"] != "canonical-reconcile" or operation["plan"] is None:
            raise ValueError("only canonical mutation candidates can be selected")
        if selection_row["target_paths"] != operation["plan"]["target_paths"]:
            raise ValueError("selected targets are partial, extra, reordered, or mismatched")
        selected_identities.add(identity)

    candidates = {
        row["repo_identity"]
        for row in census["repositories"]
        if row["proposed_operation"]["kind"] == "canonical-reconcile"
    }
    if selected_identities != candidates:
        if decision == "approved":
            raise ValueError(
                "approval must explicitly enumerate the complete batch plan; regenerate a plan containing only the intended repositories before approving a subset"
            )
        raise ValueError("rejection must explicitly enumerate the complete mutation proposal")

    result = copy.deepcopy(census)
    for row in result["repositories"]:
        authorized = decision == "approved" and row["repo_identity"] in selected_identities
        row["approval_status"] = "approved" if authorized else "rejected"
        row["eligible"] = authorized
    result["approval"] = {
        "status": decision,
        "responsible_actor": actor,
        "requested_at": captured_now.isoformat().replace("+00:00", "Z"),
        "approved_census_id": census_id if decision == "approved" else None,
    }
    counts = Counter(row["approval_status"] for row in result["repositories"])
    result["summary"]["approved"] = counts["approved"]
    result["summary"]["authorized_mutations"] = sum(
        row["approval_status"] == "approved"
        and row["eligible"]
        and row["proposed_operation"]["kind"] == "canonical-reconcile"
        and row["proposed_operation"]["plan"] is not None
        for row in result["repositories"]
    )
    if result["census_id"] != census_id or validator.census_identity(result) != census_id:
        raise ValueError("owner decision changed the immutable census identity")
    output_errors = validator.validate(result, schema, now_utc=captured_now)
    if output_errors:
        raise ValueError("owner decision artifact is invalid: " + "; ".join(output_errors))
    return result


def write_exclusive(path: Path, payload: dict[str, Any], *, input_path: Path) -> None:
    if path.resolve(strict=False) == input_path.resolve(strict=False):
        raise FileExistsError("output must not overwrite the input census")
    with path.open("x", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("census")
    parser.add_argument("--schema", default=str(Path(__file__).with_name("fleet-census.schema.json")))
    parser.add_argument("--selection", required=True, help="JSON file containing the exact reviewed mutation selection")
    parser.add_argument("--census-id", required=True)
    parser.add_argument("--actor", required=True)
    parser.add_argument("--decision", required=True, choices=("approved", "rejected"))
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    captured_now = datetime.now(timezone.utc)
    input_path = Path(args.census)
    output_path = Path(args.output)
    census = load_json(input_path)
    selection = load_json(Path(args.selection))
    schema = load_json(Path(args.schema))
    result = decide(
        census,
        selection,
        schema,
        census_id=args.census_id,
        actor=args.actor,
        decision=args.decision,
        now_utc=captured_now,
    )
    write_exclusive(output_path, result, input_path=input_path)
    print(
        json.dumps(
            {
                "approval_status": result["approval"]["status"],
                "authorized_mutations": result["summary"]["authorized_mutations"],
                "census_id": result["census_id"],
                "output": str(output_path),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
