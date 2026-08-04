#!/usr/bin/env python3
"""Validate and semantically check one disposable reconciliation lifecycle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


def _load(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _validate(schema: dict[str, Any], value: Any, *, label: str) -> None:
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(value), key=lambda item: list(item.path))
    if errors:
        rendered = "; ".join(
            f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
            for error in errors[:5]
        )
        raise SystemExit(f"{label} does not satisfy schema 1.0: {rendered}")


def _project(report: dict[str, Any], path: str) -> dict[str, Any]:
    matches = [item for item in report.get("projects", []) if item.get("path") == path]
    if len(matches) != 1:
        raise SystemExit(
            f"{report.get('phase')} did not account for the selected project exactly once"
        )
    return matches[0]


def _component(project: dict[str, Any], name: str) -> dict[str, Any]:
    matches = [
        item for item in project.get("components", []) if item.get("component") == name
    ]
    if len(matches) != 1:
        raise SystemExit(f"selected project did not contain exactly one {name} row")
    return matches[0]


def _plan(report: dict[str, Any], path: str) -> dict[str, Any]:
    matches = [item for item in report.get("plans", []) if item.get("path") == path]
    if len(matches) != 1:
        raise SystemExit("plan did not account for the selected project exactly once")
    return matches[0]


def _ledger(report: dict[str, Any], path: str) -> dict[str, Any]:
    matches = [item for item in report.get("ledger", []) if item.get("path") == path]
    if len(matches) != 1:
        raise SystemExit("apply did not account for the selected project exactly once")
    return matches[0]


def _tree_digest(root: Path) -> str:
    rows: list[list[Any]] = []
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        directories[:] = sorted(name for name in directories if name != ".git")
        for name in sorted(files):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                rows.append([relative, "symlink", os.readlink(path)])
            else:
                rows.append(
                    [relative, "file", hashlib.sha256(path.read_bytes()).hexdigest()]
                )
    payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--request-schema", type=Path, required=True)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--machine-root", type=Path, required=True)
    for phase in (
        "assess",
        "plan",
        "apply",
        "verify",
        "repeat-plan",
        "repeat-apply",
        "recover",
    ):
        parser.add_argument(f"--{phase}", type=Path, required=True)
    parser.add_argument("--expected-stable-digest", required=True)
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    schema = _load(args.schema)
    request_schema = _load(args.request_schema)
    request = _load(args.request)
    reports = {
        "assess": _load(args.assess),
        "plan": _load(args.plan),
        "apply": _load(args.apply),
        "verify": _load(args.verify),
        "repeat-plan": _load(args.repeat_plan),
        "repeat-apply": _load(args.repeat_apply),
        "recover": _load(args.recover),
    }

    _validate(request_schema, request, label="explicit request")
    for label, report in reports.items():
        _validate(schema, report, label=label)
        expected_phase = label.removeprefix("repeat-")
        if report.get("schema_version") != "1.0" or report.get("phase") != expected_phase:
            raise SystemExit(f"{label} returned the wrong schema or phase")

    project_path = str(args.project.resolve())
    root_path = str(args.project.parent.resolve())
    if request != {
        "schema_version": "1.0",
        "roots": [root_path],
        "projects": [{"path": project_path, "components": ["claude"]}],
    }:
        raise SystemExit("request is not the exact disposable Claude-only selection")

    _project(reports["assess"], project_path)
    initial_plan = _plan(reports["plan"], project_path)
    if not initial_plan.get("operations"):
        raise SystemExit("initial plan did not contain the expected setup operations")
    if initial_plan.get("recipes") != [
        {"component": "claude", "recipe_id": "claude-project-setup-v1"}
    ]:
        raise SystemExit("initial plan did not bind the reviewed Claude setup recipe")

    first_apply = reports["apply"]
    if first_apply.get("result") != "applied":
        raise SystemExit("initial apply was not successful")
    if first_apply.get("requested_plan_id") != reports["plan"].get("plan_id"):
        raise SystemExit("initial apply did not consume the reviewed plan id")
    if _ledger(first_apply, project_path).get("status") != "applied":
        raise SystemExit("initial apply did not record an applied project receipt")
    diagnostic = first_apply.get("diagnostics") or {}
    diagnostic_path = diagnostic.get("path")
    if diagnostic.get("state") != "available" or not isinstance(diagnostic_path, str):
        raise SystemExit("initial apply did not save a durable diagnostic")
    try:
        Path(diagnostic_path).resolve().relative_to(args.machine_root.resolve())
    except (OSError, ValueError) as exc:
        raise SystemExit("diagnostic escaped the disposable machine root") from exc

    verified = _project(reports["verify"], project_path)
    if verified.get("route") != "ready" or _component(verified, "claude").get(
        "state"
    ) != "ready":
        raise SystemExit("fresh verification did not classify Claude as ready")

    repeated = _plan(reports["repeat-plan"], project_path)
    if repeated.get("operations") != []:
        raise SystemExit("repeat plan proposed duplicate project work")
    repeat_apply = reports["repeat-apply"]
    if repeat_apply.get("result") != "applied":
        raise SystemExit("repeat zero-operation apply was not successful")
    if repeat_apply.get("requested_plan_id") != reports["repeat-plan"].get("plan_id"):
        raise SystemExit("repeat apply did not consume its reviewed plan id")
    repeat_receipt = _ledger(repeat_apply, project_path)
    if repeat_receipt.get("status") != "unchanged" or repeat_receipt.get(
        "completed_operation_ids"
    ) != []:
        raise SystemExit("repeat apply did not emit an unchanged zero-operation receipt")

    recovery = reports["recover"]
    if recovery.get("result") != "ready" or recovery.get("recoveries") != []:
        raise SystemExit("recovery did not report a clean terminal state")

    actual_digest = _tree_digest(args.project)
    if actual_digest != args.expected_stable_digest:
        raise SystemExit("verify/repeat/recover changed the disposable project tree")

    print(
        "reconcile schema 1.0 lifecycle PASS: "
        "assess -> plan -> apply -> verify -> zero-work repeat -> recover"
    )


if __name__ == "__main__":
    main()
